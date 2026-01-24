defmodule GraphMem.Services.Linker do
  @moduledoc """
  Automatic memory linking service.

  Links new memories to semantically similar existing memories
  using background tasks (no Oban dependency).
  """

  alias GraphMem.{Memory, AccessContext, Backend}
  alias GraphMem.Services.Graph

  @similarity_threshold 0.75
  @max_candidates 20
  @max_links 5

  @doc """
  Links a memory to similar memories asynchronously.

  Uses Task.Supervisor to run the linking in the background.
  """
  @spec link_async(Memory.t(), AccessContext.t()) :: :ok
  def link_async(%Memory{} = memory, %AccessContext{} = ctx) do
    if memory.embedding do
      Task.Supervisor.start_child(GraphMem.TaskSupervisor, fn ->
        link_sync(memory, ctx)
      end)
    end

    :ok
  end

  @doc """
  Links a memory to similar memories synchronously.
  """
  @spec link_sync(Memory.t(), AccessContext.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def link_sync(%Memory{embedding: nil}, _ctx), do: {:ok, 0}

  def link_sync(%Memory{} = memory, %AccessContext{} = ctx) do
    case find_similar_memories(memory, ctx) do
      {:ok, candidates} ->
        create_links(memory, candidates, ctx)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Manually triggers linking for a memory by ID.
  """
  @spec link_memory(binary(), AccessContext.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def link_memory(memory_id, %AccessContext{} = ctx) do
    with {:ok, memory} <- Backend.get_backend().get_memory(memory_id, ctx) do
      link_sync(memory, ctx)
    end
  end

  # Private

  defp find_similar_memories(%Memory{} = memory, %AccessContext{} = ctx) do
    opts = [
      limit: @max_candidates,
      threshold: @similarity_threshold
    ]

    case Backend.get_backend().search_memories(memory.embedding, ctx, opts) do
      {:ok, results} ->
        candidates =
          results
          |> Enum.reject(&(&1.memory.id == memory.id))
          |> Enum.filter(&(&1.score >= @similarity_threshold))
          |> Enum.take(@max_links)

        {:ok, candidates}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_links(%Memory{} = source, candidates, %AccessContext{} = ctx) do
    results =
      Enum.map(candidates, fn %{memory: target, score: sim} ->
        opts = [
          weight: sim,
          confidence: min(source.confidence || 0.7, target.confidence || 0.7),
          metadata: %{
            linked_by: "auto",
            similarity_score: sim
          }
        ]

        case Graph.link(source.id, target.id, "relates_to", opts, ctx) do
          {:ok, _edge} -> :ok
          {:error, _} -> :skip
        end
      end)

    link_count = Enum.count(results, &(&1 == :ok))
    {:ok, link_count}
  end
end
