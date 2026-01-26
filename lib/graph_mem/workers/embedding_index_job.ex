defmodule GraphMem.Workers.EmbeddingIndexJob do
  @moduledoc """
  Oban worker for async embedding computation.

  This worker is enqueued when a new memory is stored. It:
  1. Retrieves the memory from the backend
  2. Computes the embedding via the Batcher
  3. Persists the embedding back to the backend
  4. Triggers auto-linking if enabled

  ## Configuration

  The job uses the `:embeddings` queue with 3 max attempts by default.
  Configure in your Oban setup:

      config :graph_mem, Oban,
        queues: [embeddings: 10]

  ## Job Args

  - `memory_id` - The ID of the memory to index
  - `agent_id` - The agent that owns the memory
  - `tenant_id` - Optional tenant ID for multi-tenancy
  """

  use Oban.Worker,
    queue: :embeddings,
    max_attempts: 3,
    unique: [period: 60, fields: [:args], keys: [:memory_id]]

  require Logger
  alias GraphMem.{AccessContext, Backend}
  alias GraphMem.Embedding.Indexer

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{"memory_id" => memory_id, "agent_id" => agent_id} = args
    tenant_id = Map.get(args, "tenant_id")

    ctx = AccessContext.new(agent_id: agent_id, tenant_id: tenant_id)
    backend = Backend.get_backend()

    case backend.get_memory(memory_id, ctx) do
      {:ok, memory} ->
        case Indexer.do_index(memory, ctx) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, :not_found} ->
        Logger.info("Memory #{memory_id} not found, skipping embedding index")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to fetch memory #{memory_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
