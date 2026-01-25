defmodule GraphMem.Backend do
  @moduledoc """
  Behaviour for pluggable storage backends.

  Backends handle the storage, retrieval, and search of memories and edges.
  GraphMem ships with an ETS backend (default) and an optional Postgres backend.

  ## Implementing a Custom Backend

  To implement a custom backend, create a module that implements all the
  callbacks defined in this behaviour:

      defmodule MyApp.CustomBackend do
        @behaviour GraphMem.Backend

        def start_link(opts) do
          # Initialize your storage
        end

        def put_memory(memory, ctx) do
          # Store a memory
        end

        # ... implement other callbacks
      end

  Then configure GraphMem to use your backend:

      config :graph_mem,
        backend: MyApp.CustomBackend
  """

  alias GraphMem.{Memory, Edge, AccessContext}

  @type ctx :: AccessContext.t()
  @type memory :: Memory.t()
  @type edge :: Edge.t()

  # ============================================================================
  # Lifecycle
  # ============================================================================

  @doc """
  Starts the backend as a supervised process.
  """
  @callback start_link(opts :: keyword()) :: GenServer.on_start()

  @doc """
  Returns the child specification for supervision.
  """
  @callback child_spec(opts :: keyword()) :: Supervisor.child_spec()

  # ============================================================================
  # Memory Operations
  # ============================================================================

  @doc """
  Stores a memory.

  Returns `{:ok, memory}` with any backend-assigned fields (like ID).
  """
  @callback put_memory(memory(), ctx()) :: {:ok, memory()} | {:error, term()}

  @doc """
  Retrieves a memory by ID.

  Must respect access control: return `:access_denied` if the context
  cannot access the memory.
  """
  @callback get_memory(id :: binary(), ctx()) ::
              {:ok, memory()} | {:error, :not_found | :access_denied}

  @doc """
  Deletes a memory by ID.

  Should also delete any associated edges.
  """
  @callback delete_memory(id :: binary(), ctx()) :: :ok | {:error, term()}

  @doc """
  Lists all memories accessible to the context.

  ## Options

  - `:limit` - Maximum results (default: 100)
  - `:type` - Filter by memory type
  - `:tags` - Filter by tags
  """
  @callback list_memories(ctx(), opts :: keyword()) :: {:ok, [memory()]}

  # ============================================================================
  # Semantic Search
  # ============================================================================

  @doc """
  Searches for memories similar to the query embedding.

  Returns a list of memories with similarity scores, ordered by similarity.

  ## Options

  - `:limit` - Maximum results (default: 5)
  - `:threshold` - Minimum similarity score (default: 0.3)
  - `:type` - Filter by memory type
  - `:tags` - Filter by tags
  - `:min_confidence` - Minimum confidence score (default: 0.5)
  """
  @callback search_memories(query_embedding :: [number()], ctx(), opts :: keyword()) ::
              {:ok, [%{memory: memory(), score: float()}]} | {:error, term()}

  # ============================================================================
  # Edge Operations
  # ============================================================================

  @doc """
  Stores an edge between two memories.

  Returns `{:ok, edge}` with any backend-assigned fields.
  """
  @callback put_edge(edge(), ctx()) :: {:ok, edge()} | {:error, term()}

  @doc """
  Retrieves edges for a memory.

  ## Direction

  - `:outgoing` - Edges where memory is the source
  - `:incoming` - Edges where memory is the target
  - `:both` - Both directions

  ## Options

  - `:type` - Filter by edge type
  - `:min_weight` - Minimum edge weight (default: 0.0)
  - `:limit` - Maximum results (default: 50)
  """
  @callback neighbors(
              memory_id :: binary(),
              direction :: :outgoing | :incoming | :both,
              ctx(),
              opts :: keyword()
            ) ::
              {:ok, [%{memory: memory(), edge: edge()}]} | {:error, term()}

  @doc """
  Expands the graph from seed memories using depth-limited traversal.

  ## Options

  - `:depth` - Maximum traversal depth (default: 2, max: 3)
  - `:min_weight` - Minimum edge weight (default: 0.3)
  - `:min_confidence` - Minimum memory confidence (default: 0.5)
  - `:limit` - Maximum memories to return (default: 50)
  """
  @callback expand(seed_ids :: [binary()], ctx(), opts :: keyword()) ::
              {:ok, %{memories: [memory()], edges: [edge()]}} | {:error, term()}

  @doc """
  Deletes an edge between two memories.
  """
  @callback delete_edge(from_id :: binary(), to_id :: binary(), type :: binary()) ::
              :ok | {:error, term()}

  # ============================================================================
  # Helper for Getting the Configured Backend
  # ============================================================================

  @doc """
  Returns the currently configured backend module.

  Uses `GraphMem.Config.backend/0` for dynamic backend selection:
  - Postgres when `:repo` is configured and Ecto is available
  - ETS as fallback for zero-dependency usage
  """
  @spec get_backend() :: module()
  def get_backend do
    GraphMem.Config.backend()
  end
end
