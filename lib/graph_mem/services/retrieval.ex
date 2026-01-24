defmodule GraphMem.Services.Retrieval do
  @moduledoc """
  Retrieval service for semantic memory search and context formatting.
  """

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

    case Graph.expand(seed_ids, ctx, opts) do
      {:ok, %{memories: expanded_memories}} ->
        existing_ids = MapSet.new(seed_ids)

        new_results =
          expanded_memories
          |> Enum.reject(&MapSet.member?(existing_ids, &1.id))
          |> Enum.map(&%{memory: &1, score: 0.5})

        results ++ new_results

      {:error, _} ->
        results
    end
  end

  defp backend do
    Backend.get_backend()
  end
end
