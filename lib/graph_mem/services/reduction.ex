defmodule GraphMem.Services.Reduction do
  @moduledoc """
  Memory reduction and context formatting for LLM prompts.

  Takes a set of recalled memories and graph-expanded results,
  then reduces them to a coherent context suitable for prompt injection.

  ## Reduction Strategy

  1. Deduplicate memories by ID
  2. Score by relevance (similarity + confidence + importance)
  3. Prioritize by recency and access patterns
  4. Truncate to token budget
  5. Format for LLM consumption
  """

  alias GraphMem.Memory

  @default_max_tokens 2000
  @avg_chars_per_token 4

  @doc """
  Reduces a set of memories and edges to a formatted context string.

  ## Parameters

  - `data` - Map with `:memories` and optionally `:edges` and `:similarities`
  - `opts` - Options

  ## Options

  - `:max_tokens` - Maximum tokens for output (default: 2000)
  - `:include_edges` - Include edge information (default: false)
  - `:format` - Output format: `:text`, `:structured`, `:json` (default: :text)
  """
  @spec reduce(map(), keyword()) :: {:ok, binary()}
  def reduce(data, opts \\ []) do
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
    include_edges = Keyword.get(opts, :include_edges, false)
    format = Keyword.get(opts, :format, :text)

    memories = extract_memories(data)
    edges = if include_edges, do: Map.get(data, :edges, []), else: []
    similarities = Map.get(data, :similarities, %{})

    scored_memories =
      memories
      |> deduplicate()
      |> Enum.map(&score_memory(&1, similarities))
      |> Enum.sort_by(& &1.score, :desc)

    max_chars = max_tokens * @avg_chars_per_token

    {selected_memories, _} =
      Enum.reduce_while(scored_memories, {[], 0}, fn scored, {acc, chars} ->
        formatted = format_memory(scored.memory, format)
        new_chars = chars + String.length(formatted) + 10

        if new_chars <= max_chars do
          {:cont, {[scored | acc], new_chars}}
        else
          {:halt, {acc, chars}}
        end
      end)

    selected_memories = Enum.reverse(selected_memories)

    context =
      case format do
        :text -> format_as_text(selected_memories, edges)
        :structured -> format_as_structured(selected_memories, edges)
        :json -> format_as_json(selected_memories, edges)
      end

    {:ok, context}
  end

  @doc """
  Formats a single memory for prompt injection.
  """
  @spec format_memory(Memory.t(), atom()) :: binary()
  def format_memory(%Memory{} = memory, format \\ :text) do
    case format do
      :text ->
        confidence = memory.confidence || 0.5
        "[#{memory.type}] (#{Float.round(confidence, 2)}) #{memory.summary}\n#{memory.content}"

      :structured ->
        confidence = memory.confidence || 0.5

        """
        <memory id="#{memory.id}" type="#{memory.type}" confidence="#{Float.round(confidence, 2)}">
          <summary>#{memory.summary}</summary>
          <content>#{memory.content}</content>
        </memory>
        """

      :json ->
        Jason.encode!(%{
          id: memory.id,
          type: memory.type,
          summary: memory.summary,
          content: memory.content,
          confidence: memory.confidence
        })
    end
  end

  # Private

  defp extract_memories(%{memories: memories}) when is_list(memories), do: memories
  defp extract_memories(memories) when is_list(memories), do: memories
  defp extract_memories(_), do: []

  defp deduplicate(memories) do
    memories
    |> Enum.uniq_by(& &1.id)
  end

  defp score_memory(%Memory{} = memory, similarities) do
    similarity = Map.get(similarities, memory.id, 0.5)
    confidence = memory.confidence || 0.5
    importance = memory.importance || 0.5

    recency_score = calculate_recency_score(memory.inserted_at)
    access_score = calculate_access_score(memory.access_count)

    score =
      similarity * 0.35 +
        confidence * 0.25 +
        importance * 0.20 +
        recency_score * 0.10 +
        access_score * 0.10

    %{memory: memory, score: score, similarity: similarity}
  end

  defp calculate_recency_score(nil), do: 0.5

  defp calculate_recency_score(inserted_at) do
    days_ago = DateTime.diff(DateTime.utc_now(), inserted_at, :day)

    cond do
      days_ago <= 1 -> 1.0
      days_ago <= 7 -> 0.8
      days_ago <= 30 -> 0.6
      days_ago <= 90 -> 0.4
      true -> 0.2
    end
  end

  defp calculate_access_score(nil), do: 0.5
  defp calculate_access_score(0), do: 0.3

  defp calculate_access_score(count) do
    min(1.0, 0.5 + count * 0.1)
  end

  defp format_as_text(scored_memories, edges) do
    if Enum.empty?(scored_memories) do
      ""
    else
      memory_text =
        scored_memories
        |> Enum.map(fn %{memory: m, similarity: sim} ->
          confidence = m.confidence || 0.5

          "[#{m.type}] #{m.summary}\n#{m.content}\n(relevance: #{Float.round(sim, 2)}, confidence: #{Float.round(confidence, 2)})"
        end)
        |> Enum.join("\n\n---\n\n")

      edge_text =
        if Enum.empty?(edges) do
          ""
        else
          edge_summary =
            edges
            |> Enum.take(10)
            |> Enum.map(&"#{&1.from_id} --[#{&1.type}]--> #{&1.to_id}")
            |> Enum.join("\n")

          "\n\n## Memory Relationships\n#{edge_summary}"
        end

      "## Relevant Memories\n\n#{memory_text}#{edge_text}"
    end
  end

  defp format_as_structured(scored_memories, edges) do
    if Enum.empty?(scored_memories) do
      ""
    else
      memory_xml =
        scored_memories
        |> Enum.map(fn %{memory: m} -> format_memory(m, :structured) end)
        |> Enum.join("\n")

      edge_xml =
        if Enum.empty?(edges) do
          ""
        else
          edge_text =
            edges
            |> Enum.take(10)
            |> Enum.map(
              &"<edge from=\"#{&1.from_id}\" to=\"#{&1.to_id}\" type=\"#{&1.type}\" weight=\"#{&1.weight}\"/>"
            )
            |> Enum.join("\n")

          "\n<relationships>\n#{edge_text}\n</relationships>"
        end

      "<memories>\n#{memory_xml}\n</memories>#{edge_xml}"
    end
  end

  defp format_as_json(scored_memories, edges) do
    data = %{
      memories:
        Enum.map(scored_memories, fn %{memory: m, similarity: sim, score: score} ->
          %{
            id: m.id,
            type: m.type,
            summary: m.summary,
            content: m.content,
            confidence: m.confidence,
            relevance: sim,
            score: score
          }
        end),
      edges:
        Enum.map(Enum.take(edges, 20), fn e ->
          %{
            from: e.from_id,
            to: e.to_id,
            type: e.type,
            weight: e.weight
          }
        end)
    }

    Jason.encode!(data, pretty: true)
  end
end
