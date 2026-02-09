defmodule GraphMem.Backends.ETS do
  @moduledoc """
  ETS-based storage backend.

  ETS-based storage backend. Stores memories and edges in ETS tables,
  with in-memory vector similarity search. Suitable for development, testing,
  and small-scale production use.

  ## Features

  - No external dependencies
  - Fast in-memory operations
  - Automatic cleanup on process termination
  - Graph traversal via BFS

  ## Limitations

  - Data is not persisted across restarts
  - Vector search is O(n) - suitable for < 50k memories
  - Single-node only
  """

  @behaviour GraphMem.Backend

  use GenServer

  alias GraphMem.{Memory, Edge, AccessContext, EmbeddingAdapter}

  @memories_table :graph_mem_memories
  @edges_table :graph_mem_edges

  # ============================================================================
  # Lifecycle
  # ============================================================================

  @impl GraphMem.Backend
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GraphMem.Backend
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@memories_table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@edges_table, [:named_table, :bag, :public, read_concurrency: true])
    {:ok, %{}}
  end

  # ============================================================================
  # Memory Operations
  # ============================================================================

  @impl GraphMem.Backend
  def put_memory(%Memory{} = memory, %AccessContext{} = _ctx) do
    :ets.insert(@memories_table, {memory.id, memory})
    {:ok, memory}
  end

  @impl GraphMem.Backend
  def get_memory(id, %AccessContext{} = ctx) do
    case :ets.lookup(@memories_table, id) do
      [{^id, memory}] ->
        if AccessContext.can_access_memory?(ctx, memory) do
          {:ok, memory}
        else
          {:error, :access_denied}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @impl GraphMem.Backend
  def delete_memory(id, %AccessContext{} = _ctx) do
    :ets.delete(@memories_table, id)

    :ets.match_delete(@edges_table, {:_, %{from_id: id}})
    :ets.match_delete(@edges_table, {:_, %{to_id: id}})

    :ok
  end

  @impl GraphMem.Backend
  def list_memories(%AccessContext{} = ctx, opts) do
    limit = Keyword.get(opts, :limit, 100)
    type = Keyword.get(opts, :type)
    tags = Keyword.get(opts, :tags)

    memories =
      @memories_table
      |> :ets.tab2list()
      |> Enum.map(fn {_id, memory} -> memory end)
      |> Enum.filter(&AccessContext.can_access_memory?(ctx, &1))
      |> maybe_filter_type(type)
      |> maybe_filter_tags(tags)
      |> Enum.take(limit)

    {:ok, memories}
  end

  # ============================================================================
  # Semantic Search
  # ============================================================================

  @impl GraphMem.Backend
  def search_memories(query_embedding, %AccessContext{} = ctx, opts) do
    limit = Keyword.get(opts, :limit, 5)
    threshold = Keyword.get(opts, :threshold, 0.3)
    type = Keyword.get(opts, :type)
    tags = Keyword.get(opts, :tags)
    min_confidence = Keyword.get(opts, :min_confidence, 0.5)

    results =
      @memories_table
      |> :ets.tab2list()
      |> Enum.map(fn {_id, memory} -> memory end)
      |> Enum.filter(&AccessContext.can_access_memory?(ctx, &1))
      |> Enum.filter(&(not is_nil(&1.embedding)))
      |> Enum.filter(&((&1.confidence || 0.5) >= min_confidence))
      |> maybe_filter_type(type)
      |> maybe_filter_tags(tags)
      |> Enum.map(fn memory ->
        score = EmbeddingAdapter.cosine_similarity(query_embedding, memory.embedding)
        %{memory: memory, score: score}
      end)
      |> Enum.filter(&(&1.score >= threshold))
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.take(limit)

    {:ok, results}
  end

  # ============================================================================
  # Edge Operations
  # ============================================================================

  @impl GraphMem.Backend
  def put_edge(%Edge{} = edge, %AccessContext{} = _ctx) do
    key = {edge.from_id, edge.to_id, edge.type}

    case :ets.lookup(@edges_table, key) do
      [{^key, _existing}] ->
        {:ok, edge}

      [] ->
        :ets.insert(@edges_table, {key, edge})
        {:ok, edge}
    end
  end

  @impl GraphMem.Backend
  def neighbors(memory_id, direction, %AccessContext{} = ctx, opts) do
    type = Keyword.get(opts, :type)
    min_weight = Keyword.get(opts, :min_weight, 0.0)
    limit = Keyword.get(opts, :limit, 50)

    edges = get_edges_for_memory(memory_id, direction, type, min_weight)

    results =
      edges
      |> Enum.map(fn edge ->
        neighbor_id = if edge.from_id == memory_id, do: edge.to_id, else: edge.from_id

        case get_memory(neighbor_id, ctx) do
          {:ok, memory} -> %{memory: memory, edge: edge}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.take(limit)

    {:ok, results}
  end

  @impl GraphMem.Backend
  def expand(seed_ids, %AccessContext{} = ctx, opts) do
    depth = min(Keyword.get(opts, :depth, 2), 3)
    min_weight = Keyword.get(opts, :min_weight, 0.3)
    min_confidence = Keyword.get(opts, :min_confidence, 0.5)
    limit = Keyword.get(opts, :limit, 50)

    if Enum.empty?(seed_ids) do
      {:ok, %{memories: [], edges: []}}
    else
      {memories, edges} = bfs_expand(seed_ids, depth, min_weight, min_confidence, limit, ctx)
      {:ok, %{memories: memories, edges: edges}}
    end
  end

  @impl GraphMem.Backend
  def delete_edge(from_id, to_id, type) do
    key = {from_id, to_id, type}
    :ets.delete(@edges_table, key)
    :ok
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp maybe_filter_type(memories, nil), do: memories
  defp maybe_filter_type(memories, type), do: Enum.filter(memories, &(&1.type == to_string(type)))

  defp maybe_filter_tags(memories, nil), do: memories
  defp maybe_filter_tags(memories, []), do: memories

  defp maybe_filter_tags(memories, tags) when is_list(tags) do
    tag_set = MapSet.new(tags)

    Enum.filter(memories, fn memory ->
      memory_tags = MapSet.new(memory.tags || [])
      not MapSet.disjoint?(memory_tags, tag_set)
    end)
  end

  defp get_edges_for_memory(memory_id, direction, type, min_weight) do
    all_edges =
      @edges_table
      |> :ets.tab2list()
      |> Enum.map(fn {_key, edge} -> edge end)

    edges =
      case direction do
        :outgoing ->
          Enum.filter(all_edges, &(&1.from_id == memory_id))

        :incoming ->
          Enum.filter(all_edges, &(&1.to_id == memory_id))

        :both ->
          Enum.filter(all_edges, &(&1.from_id == memory_id or &1.to_id == memory_id))
      end

    edges
    |> Enum.filter(&(&1.weight >= min_weight))
    |> maybe_filter_edge_type(type)
  end

  defp maybe_filter_edge_type(edges, nil), do: edges
  defp maybe_filter_edge_type(edges, type), do: Enum.filter(edges, &(&1.type == to_string(type)))

  defp bfs_expand(seed_ids, max_depth, min_weight, min_confidence, limit, ctx) do
    visited = MapSet.new(seed_ids)

    {final_memories, final_edges, _visited} =
      Enum.reduce(0..max_depth, {[], [], visited}, fn depth, {memories, edges, visited} ->
        if depth == 0 do
          initial_memories =
            seed_ids
            |> Enum.map(&get_memory(&1, ctx))
            |> Enum.filter(&match?({:ok, _}, &1))
            |> Enum.map(fn {:ok, m} -> m end)
            |> Enum.filter(&((&1.confidence || 0.5) >= min_confidence))

          {initial_memories, edges, visited}
        else
          current_ids = Enum.map(memories, & &1.id)

          new_neighbors =
            current_ids
            |> Enum.flat_map(fn id ->
              case neighbors(id, :outgoing, ctx, min_weight: min_weight) do
                {:ok, results} -> results
                _ -> []
              end
            end)
            |> Enum.reject(&MapSet.member?(visited, &1.memory.id))
            |> Enum.filter(&((&1.memory.confidence || 0.5) >= min_confidence))

          new_memories = Enum.map(new_neighbors, & &1.memory)
          new_edges = Enum.map(new_neighbors, & &1.edge)
          new_visited = Enum.reduce(new_memories, visited, &MapSet.put(&2, &1.id))

          total_memories = memories ++ new_memories
          total_edges = edges ++ new_edges

          if length(total_memories) >= limit do
            {Enum.take(total_memories, limit), total_edges, new_visited}
          else
            {total_memories, total_edges, new_visited}
          end
        end
      end)

    {Enum.take(final_memories, limit), final_edges}
  end
end
