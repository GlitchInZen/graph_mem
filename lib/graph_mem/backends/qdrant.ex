defmodule GraphMem.Backends.Qdrant do
  @moduledoc """
  Qdrant-based storage backend using a single collection for memories and edges.

  This backend stores both memory records and edge records in the same Qdrant
  collection using payloads to differentiate record types. Vector search is
  performed on memory records only, while edge traversal is handled in Elixir
  via BFS expansion.

  ## Requirements

  - Qdrant instance (local or hosted)
  - `req` HTTP client dependency (already included)

  ## Configuration

      config :graph_mem,
        backend: GraphMem.Backends.Qdrant,
        qdrant_url: "http://localhost:6333",
        qdrant_api_key: System.get_env("QDRANT_API_KEY"),
        qdrant_collection: "graph_mem",
        embedding_dimensions: 768
  """

  @behaviour GraphMem.Backend

  use GenServer

  alias GraphMem.{AccessContext, Edge, Memory, Config}

  @memory_record "memory"
  @edge_record "edge"

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
  def init(opts) do
    url = Keyword.get(opts, :qdrant_url) || Config.qdrant_url()
    collection = Keyword.get(opts, :qdrant_collection) || Config.qdrant_collection()
    dimensions = Config.embedding_dimensions()

    unless url do
      raise ArgumentError, "GraphMem.Backends.Qdrant requires :qdrant_url to be configured"
    end

    :ok = ensure_collection(url, collection, dimensions)

    {:ok, %{url: url, collection: collection, dimensions: dimensions}}
  end

  # ============================================================================
  # Memory Operations
  # ============================================================================

  @impl GraphMem.Backend
  def put_memory(%Memory{} = memory, %AccessContext{} = _ctx) do
    payload = memory_payload(memory)

    point = %{
      id: memory.id,
      vector: memory_vector(memory.embedding),
      payload: payload
    }

    with {:ok, _} <- upsert_points([point]) do
      {:ok, memory}
    end
  end

  @impl GraphMem.Backend
  def get_memory(id, %AccessContext{} = ctx) do
    case retrieve_point(id) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, %{"payload" => _payload} = point} ->
        memory = payload_to_memory(point)

        if AccessContext.can_access_memory?(ctx, memory) do
          {:ok, memory}
        else
          {:error, :access_denied}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl GraphMem.Backend
  def delete_memory(id, %AccessContext{} = _ctx) do
    with {:ok, _} <- delete_points([id]),
         {:ok, edge_ids} <- find_edge_ids_for_memory(id),
         {:ok, _} <- delete_points(edge_ids) do
      :ok
    end
  end

  @impl GraphMem.Backend
  def list_memories(%AccessContext{} = ctx, opts) do
    limit = Keyword.get(opts, :limit, 100)
    type = Keyword.get(opts, :type)
    tags = Keyword.get(opts, :tags)

    filter =
      ctx
      |> base_memory_filter()
      |> maybe_filter_type(type)
      |> maybe_filter_tags(tags)

    with {:ok, points} <- scroll_points(filter, limit) do
      memories =
        points
        |> Enum.map(&payload_to_memory/1)

      {:ok, memories}
    end
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

    filter =
      ctx
      |> base_memory_filter()
      |> filter_has_embedding()
      |> maybe_filter_type(type)
      |> maybe_filter_tags(tags)
      |> maybe_filter_min_confidence(min_confidence)

    with {:ok, points} <- search_points(query_embedding, limit, threshold, filter) do
      results =
        Enum.map(points, fn %{"payload" => _payload, "score" => score} = point ->
          memory = payload_to_memory(point)
          %{memory: memory, score: score}
        end)

      {:ok, results}
    end
  end

  # ============================================================================
  # Edge Operations
  # ============================================================================

  @impl GraphMem.Backend
  def put_edge(%Edge{} = edge, %AccessContext{} = _ctx) do
    payload = edge_payload(edge)
    point = %{id: edge.id, vector: memory_vector(nil), payload: payload}

    with {:ok, _} <- upsert_points([point]) do
      {:ok, edge}
    end
  end

  @impl GraphMem.Backend
  def neighbors(memory_id, direction, %AccessContext{} = ctx, opts) do
    type = Keyword.get(opts, :type)
    min_weight = Keyword.get(opts, :min_weight, 0.0)
    limit = Keyword.get(opts, :limit, 50)

    with {:ok, edges} <- fetch_edges_for_memory(memory_id, direction, type, min_weight, limit) do
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

      {:ok, results}
    end
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
    filter =
      edge_filter_base()
      |> put_in([:must], [
        match_condition("from_id", from_id),
        match_condition("to_id", to_id),
        match_condition("type", to_string(type))
      ])

    with {:ok, points} <- scroll_points(filter, 100),
         ids <- Enum.map(points, & &1["id"]),
         {:ok, _} <- delete_points(ids) do
      :ok
    end
  end

  # ============================================================================
  # Internal Helpers
  # ============================================================================

  defp ensure_collection(url, collection, dimensions) do
    case request(:get, url, "/collections/#{collection}", nil) do
      {:ok, _} ->
        :ok

      {:error, _} ->
        body = %{
          vectors: %{size: dimensions, distance: "Cosine"}
        }

        with {:ok, _} <- request(:put, url, "/collections/#{collection}", body) do
          :ok
        end
    end
  end

  defp upsert_points(points) do
    body = %{points: points}
    request(:put, qdrant_url(), "/collections/#{qdrant_collection()}/points?wait=true", body)
  end

  defp retrieve_point(id) do
    case request(:get, qdrant_url(), "/collections/#{qdrant_collection()}/points/#{id}", nil) do
      {:ok, %{"result" => result}} -> {:ok, result}
      {:ok, %{"status" => "error"}} -> {:ok, nil}
      {:error, _} = error -> error
    end
  end

  defp delete_points([]), do: {:ok, :skipped}

  defp delete_points(ids) do
    body = %{points: ids}

    request(
      :post,
      qdrant_url(),
      "/collections/#{qdrant_collection()}/points/delete?wait=true",
      body
    )
  end

  defp scroll_points(filter, limit) do
    body = %{
      limit: limit,
      with_payload: true,
      with_vectors: false,
      filter: filter
    }

    case request(:post, qdrant_url(), "/collections/#{qdrant_collection()}/points/scroll", body) do
      {:ok, %{"result" => %{"points" => points}}} -> {:ok, points}
      {:ok, _} -> {:ok, []}
      {:error, _} = error -> error
    end
  end

  defp search_points(query_embedding, limit, threshold, filter) do
    body = %{
      vector: query_embedding,
      limit: limit,
      with_payload: true,
      with_vectors: false,
      score_threshold: threshold,
      filter: filter
    }

    case request(:post, qdrant_url(), "/collections/#{qdrant_collection()}/points/search", body) do
      {:ok, %{"result" => result}} -> {:ok, result}
      {:error, _} = error -> error
    end
  end

  defp fetch_edges_for_memory(memory_id, direction, type, min_weight, limit) do
    filter =
      memory_id
      |> edge_filter_for_direction(direction)
      |> maybe_filter_edge_type(type)
      |> maybe_filter_min_weight(min_weight)

    with {:ok, points} <- scroll_points(filter, limit) do
      edges = Enum.map(points, &payload_to_edge/1)
      {:ok, edges}
    end
  end

  defp edge_filter_for_direction(memory_id, direction) do
    base = edge_filter_base()

    case direction do
      :outgoing ->
        put_in(base, [:must], [match_condition("from_id", memory_id)])

      :incoming ->
        put_in(base, [:must], [match_condition("to_id", memory_id)])

      :both ->
        Map.put(base, :should, [
          %{must: [match_condition("from_id", memory_id)]},
          %{must: [match_condition("to_id", memory_id)]}
        ])
    end
  end

  defp edge_filter_base do
    %{
      must: [match_condition("record_type", @edge_record)]
    }
  end

  defp find_edge_ids_for_memory(memory_id) do
    filter = %{
      must: [match_condition("record_type", @edge_record)],
      should: [
        %{must: [match_condition("from_id", memory_id)]},
        %{must: [match_condition("to_id", memory_id)]}
      ]
    }

    with {:ok, points} <- scroll_points(filter, 500) do
      {:ok, Enum.map(points, & &1["id"])}
    end
  end

  defp base_memory_filter(%AccessContext{} = ctx) do
    %{
      must: [match_condition("record_type", @memory_record)],
      should: scope_filters(ctx)
    }
  end

  defp scope_filters(%AccessContext{} = ctx) do
    private_filter = %{
      must: [
        match_condition("scope", "private"),
        match_condition("agent_id", ctx.agent_id)
      ]
    }

    shared_filter =
      if AccessContext.can_read?(ctx, "shared") do
        tenant_filters =
          case ctx.tenant_id do
            nil ->
              [match_condition("scope", "shared")]

            tenant_id ->
              [match_condition("scope", "shared"), match_condition("tenant_id", tenant_id)]
          end

        %{must: tenant_filters}
      else
        nil
      end

    global_filter =
      if AccessContext.can_read?(ctx, "global") do
        %{must: [match_condition("scope", "global")]}
      else
        nil
      end

    [private_filter, shared_filter, global_filter]
    |> Enum.reject(&is_nil/1)
  end

  defp filter_has_embedding(filter) do
    update_filter(filter, match_condition("has_embedding", true))
  end

  defp maybe_filter_type(filter, nil), do: filter

  defp maybe_filter_type(filter, type) do
    update_filter(filter, match_condition("type", to_string(type)))
  end

  defp maybe_filter_tags(filter, nil), do: filter
  defp maybe_filter_tags(filter, []), do: filter

  defp maybe_filter_tags(filter, tags) when is_list(tags) do
    update_filter(filter, %{
      key: "tags",
      match: %{any: tags}
    })
  end

  defp maybe_filter_min_confidence(filter, min_confidence) do
    update_filter(filter, %{
      key: "confidence",
      range: %{gte: min_confidence}
    })
  end

  defp maybe_filter_edge_type(filter, nil), do: filter

  defp maybe_filter_edge_type(filter, type) do
    update_filter(filter, match_condition("type", to_string(type)))
  end

  defp maybe_filter_min_weight(filter, min_weight) do
    update_filter(filter, %{
      key: "weight",
      range: %{gte: min_weight}
    })
  end

  defp update_filter(filter, condition) do
    Map.update(filter, :must, [condition], fn must -> must ++ [condition] end)
  end

  defp match_condition(key, value) do
    %{key: key, match: %{value: value}}
  end

  defp memory_payload(%Memory{} = memory) do
    %{
      id: memory.id,
      record_type: @memory_record,
      type: memory.type,
      summary: memory.summary,
      content: memory.content,
      importance: memory.importance,
      confidence: memory.confidence,
      scope: memory.scope,
      agent_id: memory.agent_id,
      tenant_id: memory.tenant_id,
      tags: memory.tags || [],
      metadata: memory.metadata || %{},
      session_id: memory.session_id,
      access_count: memory.access_count || 0,
      last_accessed_at: format_datetime(memory.last_accessed_at),
      inserted_at: format_datetime(memory.inserted_at),
      updated_at: format_datetime(memory.updated_at),
      has_embedding: not is_nil(memory.embedding)
    }
  end

  defp edge_payload(%Edge{} = edge) do
    %{
      id: edge.id,
      record_type: @edge_record,
      from_id: edge.from_id,
      to_id: edge.to_id,
      type: edge.type,
      weight: edge.weight,
      confidence: edge.confidence,
      scope: edge.scope,
      metadata: edge.metadata || %{},
      inserted_at: format_datetime(edge.inserted_at)
    }
  end

  defp payload_to_memory(%{"payload" => payload, "id" => id}) do
    %Memory{
      id: payload["id"] || id,
      type: payload["type"],
      summary: payload["summary"],
      content: payload["content"],
      importance: payload["importance"],
      confidence: payload["confidence"],
      scope: payload["scope"],
      agent_id: payload["agent_id"],
      tenant_id: payload["tenant_id"],
      tags: payload["tags"] || [],
      metadata: payload["metadata"] || %{},
      session_id: payload["session_id"],
      access_count: payload["access_count"] || 0,
      last_accessed_at: parse_datetime(payload["last_accessed_at"]),
      inserted_at: parse_datetime(payload["inserted_at"]),
      updated_at: parse_datetime(payload["updated_at"]),
      embedding: nil
    }
  end

  defp payload_to_edge(%{"payload" => payload, "id" => id}) do
    %Edge{
      id: payload["id"] || id,
      from_id: payload["from_id"],
      to_id: payload["to_id"],
      type: payload["type"],
      weight: payload["weight"],
      confidence: payload["confidence"],
      scope: payload["scope"],
      metadata: payload["metadata"] || %{},
      inserted_at: parse_datetime(payload["inserted_at"])
    }
  end

  defp memory_vector(nil) do
    dimensions = Config.embedding_dimensions()
    List.duplicate(0.0, dimensions)
  end

  defp memory_vector(embedding) when is_list(embedding), do: embedding

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

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

  defp request(method, base_url, path, body) do
    headers =
      case Config.qdrant_api_key() do
        nil -> []
        key -> [{"api-key", key}]
      end

    req =
      Req.new(
        base_url: base_url,
        headers: headers,
        json: body,
        retry: false
      )

    case Req.request(req, method: method, url: path) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp qdrant_url, do: Config.qdrant_url()
  defp qdrant_collection, do: Config.qdrant_collection()
end
