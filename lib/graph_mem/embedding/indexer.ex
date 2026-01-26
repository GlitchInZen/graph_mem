defmodule GraphMem.Embedding.Indexer do
  @moduledoc """
  Async indexer that computes embeddings (via the batcher) and updates the
  backend with the resulting vector.

  Behavior:
  - `index_memory_async/2` enqueues work (Oban if configured, otherwise TaskSupervisor).
  - Worker computes embedding via GraphMem.Embedding.Batcher.request/2 and updates the memory row.
  - On success, triggers Linker.link_async/2 if auto-linking is enabled.

  ## Oban Integration

  To use Oban for durable job processing:

  1. Add `use_oban: true` to your config
  2. Define `GraphMem.Workers.EmbeddingIndexJob` worker module
  3. Ensure Oban is in your deps and started

  Otherwise, falls back to Task.Supervisor.
  """

  require Logger
  alias GraphMem.{Memory, AccessContext}
  alias GraphMem.Services.Linker

  @doc """
  Enqueues async embedding indexing for a memory.

  Returns `:ok` on successful enqueue, `{:error, reason}` on failure.
  """
  @spec index_memory_async(Memory.t(), AccessContext.t()) :: :ok | {:error, term()}
  def index_memory_async(%Memory{} = memory, %AccessContext{} = ctx) do
    use_oban = Application.get_env(:graph_mem, :use_oban, false)
    task_supervisor = Application.get_env(:graph_mem, :task_supervisor, GraphMem.TaskSupervisor)

    cond do
      use_oban and oban_available?() ->
        enqueue_oban_job(memory, ctx)

      true ->
        enqueue_task(memory, ctx, task_supervisor)
    end
  end

  defp oban_available? do
    Code.ensure_loaded?(Oban) and Process.whereis(Oban) != nil
  end

  defp enqueue_oban_job(memory, ctx) do
    if Code.ensure_loaded?(GraphMem.Workers.EmbeddingIndexJob) do
      args = %{memory_id: memory.id, agent_id: ctx.agent_id, tenant_id: ctx.tenant_id}

      case GraphMem.Workers.EmbeddingIndexJob.new(args) |> Oban.insert() do
        {:ok, _job} -> :ok
        {:error, reason} -> {:error, {:oban_insert_failed, reason}}
      end
    else
      Logger.warning(
        "Oban enabled but GraphMem.Workers.EmbeddingIndexJob not defined; falling back to Task"
      )

      task_supervisor = Application.get_env(:graph_mem, :task_supervisor, GraphMem.TaskSupervisor)
      enqueue_task(memory, ctx, task_supervisor)
    end
  end

  defp enqueue_task(memory, ctx, task_supervisor) do
    case Task.Supervisor.start_child(task_supervisor, fn -> do_index(memory, ctx) end) do
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, {:task_start_failed, reason}}
    end
  end

  @doc """
  Synchronous worker function that computes embedding and persists it.

  This is called by the background task or Oban worker.
  """
  @spec do_index(Memory.t(), AccessContext.t()) :: :ok | {:error, term()}
  def do_index(%Memory{} = memory, %AccessContext{} = ctx) do
    opts = []

    case GraphMem.Embedding.Batcher.request(memory.content, opts) do
      {:ok, embedding} ->
        persist_and_link(memory, embedding, ctx)

      {:error, reason} ->
        Logger.warning("Embedding failed for memory=#{memory.id}: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Indexer failed for memory=#{memory.id}: #{Exception.format(:error, e)}")
      {:error, {:exception, e}}
  end

  defp persist_and_link(memory, embedding, ctx) do
    memory_with_embedding = %{memory | embedding: embedding}
    backend = GraphMem.Backend.get_backend()

    case backend.put_memory(memory_with_embedding, ctx) do
      {:ok, updated_memory} ->
        if Application.get_env(:graph_mem, :auto_link, true) do
          Linker.link_async(updated_memory, ctx)
        end

        :ok

      {:error, reason} ->
        Logger.error("Failed to persist embedding for memory=#{memory.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
