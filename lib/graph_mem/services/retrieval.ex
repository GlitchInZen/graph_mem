defmodule GraphMem.Services.Retrieval do
  @moduledoc """
  Retrieval service for semantic memory search and context formatting.
  """

  require Logger

  alias GraphMem.{AccessContext, Backend, EmbeddingAdapter}
  alias GraphMem.Services.{Graph, Reduction}

  @doc """
  Recalls memories relevant to a query using semantic similarity.
  """
  @spec recall(binary(), AccessContext.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def recall(query, %AccessContext{} = ctx, opts \\ []) do
    case EmbeddingAdapter.embed(query) do
      {:ok, query_embedding} ->
        with {:ok, results} <- backend().search_memories(query_embedding, ctx, opts) do
          results = maybe_expand_graph(results, ctx, opts)
          {:ok, results}
        end

      {:error, :no_embedding_adapter} ->
        Logger.warning("GraphMem recall skipped: no embedding adapter configured")
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Recalls memories and formats them for LLM context injection.
  """
  @spec recall_context(binary(), AccessContext.t(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def recall_context(query, %AccessContext{} = ctx, opts \\ []) do
    with {:ok, results} <- recall(query, ctx, opts) do
      memories = Enum.map(results, & &1.memory)
      similarities = Map.new(results, fn %{memory: m, score: s} -> {m.id, s} end)

      Reduction.reduce(%{memories: memories, similarities: similarities}, opts)
    end
  end

  # Private

  defp maybe_expand_graph(results, ctx, opts) do
    if Keyword.get(opts, :expand_graph, false) do
      expand_results(results, ctx, opts)
    else
      results
    end
  end

  defp expand_results(results, ctx, opts) do
    seed_ids = Enum.map(results, & &1.memory.id)

    case Graph.expand(seed_ids, ctx, graph_expand_opts(opts)) do
      {:ok, %{memories: expanded_memories}} ->
        merge_expanded_results(results, expanded_memories, opts)

      {:error, _} ->
        results
    end
  end

  defp graph_expand_opts(opts) do
    opts
    |> Keyword.put_new(:depth, Keyword.get(opts, :graph_depth, 1))
  end

  defp merge_expanded_results(results, expanded_memories, opts) do
    threshold = Keyword.get(opts, :threshold, 0.3)
    limit = Keyword.get(opts, :limit, 5)
    base_map = Map.new(results, fn %{memory: memory, score: score} -> {memory.id, score} end)

    merged_scores =
      Enum.reduce(expanded_memories, base_map, fn memory, acc ->
        Map.update(acc, memory.id, 0.5, &max(&1, 0.5))
      end)

    merged_memories =
      expanded_memories
      |> Enum.reduce(Map.new(results, fn %{memory: memory} -> {memory.id, memory} end), fn memory,
                                                                                           acc ->
        Map.put(acc, memory.id, memory)
      end)

    merged_scores
    |> Enum.map(fn {id, score} -> %{memory: Map.fetch!(merged_memories, id), score: score} end)
    |> Enum.filter(&(&1.score >= threshold))
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(limit)
  end

  defp backend do
    Backend.get_backend()
  end
end
