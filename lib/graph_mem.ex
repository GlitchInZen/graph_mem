defmodule GraphMem do
  @moduledoc """
  Graph-based long-term memory for AI agents.

  GraphMem provides persistent memory for AI agents with automatic relationship
  discovery, semantic search, and graph-based retrieval. Memories are isolated
  by agent by default, with optional shared and global scopes for multi-agent
  coordination.

  ## Features

  - **Semantic memory recall** via vector embeddings
  - **Graph-based relationships** between memories
  - **Multi-agent isolation** with scoped sharing
  - **Pluggable backends** (ETS default, Postgres optional)
  - **Pluggable embedding adapters** (Ollama, OpenAI)

  ## Quick Start

      # Start GraphMem (usually in your supervision tree)
      GraphMem.start_link()

      # Store a memory
      {:ok, memory} = GraphMem.remember("agent_1", "Paris is the capital of France")

      # Recall relevant memories
      {:ok, results} = GraphMem.recall("agent_1", "What is the capital of France?")

      # Generate a reflection from related memories
      {:ok, reflection} = GraphMem.reflect("agent_1", topic: "geography")

  ## Configuration

      config :graph_mem,
        backend: GraphMem.Backends.ETS,
        embedding_adapter: GraphMem.EmbeddingAdapters.Ollama,
        embedding_model: "nomic-embed-text",
        ollama_endpoint: "http://localhost:11434",
        auto_link: true,
        link_threshold: 0.75

  ## Memory Types

  - `:fact` - Learned facts about users or domain knowledge
  - `:conversation` - Key points from chat sessions
  - `:episodic` - Specific events or interactions
  - `:reflection` - Synthesized insights from multiple memories
  - `:observation` - Runtime observations from agent activity
  - `:decision` - Recorded decisions and their rationale

  ## Access Scopes

  - `:private` - Only accessible by the owning agent (default)
  - `:shared` - Accessible by agents in the same tenant
  - `:global` - Accessible by all agents
  """

  require Logger

  alias GraphMem.{Memory, Edge, AccessContext}
  alias GraphMem.Services.{Storage, Retrieval, Graph}
  alias GraphMem.Embedding.Indexer

  @doc """
  Starts the GraphMem application.

  This is typically called from your application's supervision tree.
  """
  def start_link(opts \\ []) do
    GraphMem.Supervisor.start_link(opts)
  end

  @doc """
  Returns a child specification for the GraphMem supervisor.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  # ============================================================================
  # Core Agent API
  # ============================================================================

  @doc """
  Stores a new memory for an agent.

  ## Parameters

  - `agent_id` - Unique identifier for the agent
  - `text` - The content to remember (will be used for summary and content)
  - `opts` - Options

  ## Options

  - `:type` - Memory type (default: `:fact`)
  - `:summary` - Brief summary (default: first 100 chars of text)
  - `:importance` - Score from 0.0 to 1.0 (default: 0.5)
  - `:confidence` - Reliability score 0.0 to 1.0 (default: 0.7)
  - `:scope` - Access scope: `:private`, `:shared`, `:global` (default: `:private`)
  - `:tenant_id` - Tenant ID for multi-tenancy
  - `:tags` - List of tags for filtering
  - `:metadata` - Additional structured data
  - `:session_id` - Associated session ID
  - `:link` - Whether to auto-link to similar memories (default: config value)

  ## Examples

      {:ok, memory} = GraphMem.remember("agent_1", "User prefers dark mode")

      {:ok, memory} = GraphMem.remember("agent_1", "Deploy v1.2 caused errors",
        type: :observation,
        importance: 0.8,
        confidence: 0.9,
        scope: :shared,
        tags: ["deploy", "incident"]
      )
  """
  @spec remember(binary(), binary(), keyword()) :: {:ok, Memory.t()} | {:error, term()}
  def remember(agent_id, text, opts \\ []) do
    ctx = build_context(agent_id, opts)

    attrs = %{
      type: Keyword.get(opts, :type, :fact) |> to_string(),
      summary: Keyword.get(opts, :summary) || truncate(text, 100),
      content: text,
      importance: Keyword.get(opts, :importance, 0.5),
      confidence: Keyword.get(opts, :confidence, 0.7),
      scope: Keyword.get(opts, :scope, :private) |> to_string(),
      agent_id: agent_id,
      tenant_id: ctx.tenant_id,
      tags: Keyword.get(opts, :tags, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      session_id: Keyword.get(opts, :session_id)
    }

    with {:ok, memory} <- Storage.store(attrs, ctx) do
      # Enqueue async indexing (embedding + persistence + auto-linking).
      # Indexer handles linking after embedding is computed.
      case Indexer.index_memory_async(memory, ctx) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("Async indexing enqueue failed: #{inspect(reason)}")
      end

      {:ok, memory}
    end
  end

  @doc """
  Recalls memories relevant to a query using semantic similarity.

  ## Parameters

  - `agent_id` - Agent performing the recall
  - `query` - Text to search for similar memories
  - `opts` - Options

  ## Options

  - `:limit` - Maximum memories to return (default: 5)
  - `:threshold` - Minimum similarity score 0.0-1.0 (default: 0.3)
  - `:type` - Filter by memory type
  - `:tags` - Filter by tags (any match)
  - `:min_confidence` - Minimum confidence (default: 0.5)
  - `:expand_graph` - Include graph-connected memories (default: false)
  - `:graph_depth` - Expansion depth if expand_graph is true (default: 1)
  - `:tenant_id` - Tenant ID for scoping
  - `:allow_shared` - Include shared memories (default: false)
  - `:allow_global` - Include global memories (default: false)

  ## Examples

      {:ok, results} = GraphMem.recall("agent_1", "user preferences")

      {:ok, results} = GraphMem.recall("agent_1", "deployment issues",
        limit: 10,
        type: :observation,
        tags: ["deploy"],
        expand_graph: true,
        graph_depth: 2
      )

  ## Returns

      {:ok, [%{memory: %Memory{}, score: 0.87}, ...]}
  """
  @spec recall(binary(), binary(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def recall(agent_id, query, opts \\ []) do
    ctx = build_context(agent_id, opts)
    Retrieval.recall(query, ctx, opts)
  end

  @doc """
  Recalls memories and formats them for LLM context injection.

  Similar to `recall/3` but returns a formatted string suitable for
  including in system prompts.

  ## Options

  Same as `recall/3`, plus:

  - `:format` - Output format: `:text`, `:structured`, `:json` (default: `:text`)
  - `:max_tokens` - Token budget for context (default: 2000)
  - `:include_edges` - Include relationship info (default: false)

  ## Examples

      {:ok, context} = GraphMem.recall_context("agent_1", "user history",
        limit: 5,
        format: :structured
      )
  """
  @spec recall_context(binary(), binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  def recall_context(agent_id, query, opts \\ []) do
    ctx = build_context(agent_id, opts)
    Retrieval.recall_context(query, ctx, opts)
  end

  @doc """
  Generates a reflection by synthesizing related memories.

  Reflections are higher-level insights derived from clusters of
  semantically similar memories.

  ## Parameters

  - `agent_id` - Agent to reflect on
  - `opts` - Options

  ## Options

  - `:topic` - Focus topic for reflection
  - `:min_memories` - Minimum memories required (default: 3)
  - `:max_memories` - Maximum memories to include (default: 15)
  - `:reflection_adapter` - Custom reflection adapter
  - `:store` - Whether to store the reflection (default: true)
  - `:tenant_id` - Tenant ID for scoping

  ## Examples

      {:ok, reflection} = GraphMem.reflect("agent_1", topic: "user preferences")

      {:ok, reflection} = GraphMem.reflect("agent_1",
        topic: "deployment incidents",
        min_memories: 5,
        store: false
      )
  """
  @spec reflect(binary(), keyword()) :: {:ok, Memory.t() | binary()} | {:error, term()}
  def reflect(agent_id, opts \\ []) do
    ctx = build_context(agent_id, opts)
    topic = Keyword.get(opts, :topic)
    min_memories = Keyword.get(opts, :min_memories, 3)
    max_memories = Keyword.get(opts, :max_memories, 15)
    should_store = Keyword.get(opts, :store, true)

    query = topic || "important observations, facts, and decisions"

    with {:ok, results} when length(results) >= min_memories <-
           recall(agent_id, query, Keyword.merge(opts, limit: max_memories)) do
      memories = Enum.map(results, & &1.memory)

      case generate_reflection(memories, topic, opts) do
        {:ok, reflection_text} when should_store ->
          store_reflection(reflection_text, memories, ctx)

        {:ok, reflection_text} ->
          {:ok, reflection_text}

        error ->
          error
      end
    else
      {:ok, _} -> {:error, :insufficient_memories}
      error -> error
    end
  end

  # ============================================================================
  # Graph Operations
  # ============================================================================

  @doc """
  Creates an edge between two memories.

  ## Parameters

  - `agent_id` - Agent creating the link
  - `from_id` - Source memory ID
  - `to_id` - Target memory ID
  - `type` - Edge type (default: "relates_to")
  - `opts` - Options

  ## Edge Types

  - `"relates_to"` - General semantic relationship
  - `"supports"` - Target reinforces source
  - `"contradicts"` - Target conflicts with source
  - `"causes"` - Source causes/leads to target
  - `"follows"` - Temporal ordering

  ## Options

  - `:weight` - Relationship strength 0.0-1.0 (default: 0.5)
  - `:confidence` - Edge reliability (default: 0.7)
  - `:metadata` - Additional data

  ## Examples

      {:ok, edge} = GraphMem.link("agent_1", mem1_id, mem2_id, "supports", weight: 0.8)
  """
  @spec link(binary(), binary(), binary(), binary(), keyword()) ::
          {:ok, Edge.t()} | {:error, term()}
  def link(agent_id, from_id, to_id, type \\ "relates_to", opts \\ []) do
    ctx = build_context(agent_id, opts)
    Graph.link(from_id, to_id, type, opts, ctx)
  end

  @doc """
  Gets neighboring memories connected by edges.

  ## Parameters

  - `agent_id` - Agent making the request
  - `memory_id` - Memory to find neighbors for
  - `direction` - `:outgoing`, `:incoming`, or `:both` (default: `:outgoing`)
  - `opts` - Options

  ## Options

  - `:type` - Filter by edge type
  - `:min_weight` - Minimum edge weight (default: 0.0)
  - `:limit` - Maximum results (default: 50)

  ## Returns

      {:ok, [%{memory: %Memory{}, edge: %Edge{}}, ...]}
  """
  @spec neighbors(binary(), binary(), atom(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def neighbors(agent_id, memory_id, direction \\ :outgoing, opts \\ []) do
    ctx = build_context(agent_id, opts)
    Graph.neighbors(memory_id, direction, ctx, opts)
  end

  @doc """
  Expands the graph from seed memories using depth-limited traversal.

  ## Parameters

  - `agent_id` - Agent making the request
  - `seed_ids` - List of memory IDs to start from
  - `opts` - Options

  ## Options

  - `:depth` - Maximum traversal depth (default: 2, max: 3)
  - `:min_weight` - Minimum edge weight (default: 0.3)
  - `:min_confidence` - Minimum memory confidence (default: 0.5)
  - `:limit` - Maximum memories to return (default: 50)

  ## Returns

      {:ok, %{memories: [...], edges: [...]}}
  """
  @spec expand(binary(), [binary()], keyword()) :: {:ok, map()} | {:error, term()}
  def expand(agent_id, seed_ids, opts \\ []) do
    ctx = build_context(agent_id, opts)
    Graph.expand(seed_ids, ctx, opts)
  end

  # ============================================================================
  # Memory Management
  # ============================================================================

  @doc """
  Gets a memory by ID.
  """
  @spec get_memory(binary(), binary(), keyword()) ::
          {:ok, Memory.t()} | {:error, :not_found | :access_denied}
  def get_memory(agent_id, memory_id, opts \\ []) do
    ctx = build_context(agent_id, opts)
    Storage.get(memory_id, ctx)
  end

  @doc """
  Deletes a memory by ID.
  """
  @spec delete_memory(binary(), binary(), keyword()) :: :ok | {:error, term()}
  def delete_memory(agent_id, memory_id, opts \\ []) do
    ctx = build_context(agent_id, opts)
    Storage.delete(memory_id, ctx)
  end

  @doc """
  Lists all memories for an agent.
  """
  @spec list_memories(binary(), keyword()) :: {:ok, [Memory.t()]}
  def list_memories(agent_id, opts \\ []) do
    ctx = build_context(agent_id, opts)
    Storage.list(ctx, opts)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_context(agent_id, opts) do
    AccessContext.new(
      agent_id: agent_id,
      tenant_id: Keyword.get(opts, :tenant_id),
      allow_shared: Keyword.get(opts, :allow_shared, false),
      allow_global: Keyword.get(opts, :allow_global, false),
      permissions: Keyword.get(opts, :permissions, [])
    )
  end

  defp truncate(text, max_length) when byte_size(text) <= max_length, do: text

  defp truncate(text, max_length) do
    String.slice(text, 0, max_length) <> "..."
  end

  defp generate_reflection(memories, topic, opts) do
    adapter = Keyword.get(opts, :reflection_adapter) || get_reflection_adapter()

    if adapter do
      adapter.reflect(memories, topic)
    else
      {:ok, default_reflection(memories, topic)}
    end
  end

  defp get_reflection_adapter do
    Application.get_env(:graph_mem, :reflection_adapter)
  end

  defp default_reflection(memories, topic) do
    topic_text = if topic, do: " about #{topic}", else: ""

    memories_text =
      memories
      |> Enum.map(fn m -> "- [#{m.type}] #{m.summary}" end)
      |> Enum.join("\n")

    """
    Reflection#{topic_text} from #{length(memories)} memories:

    #{memories_text}
    """
  end

  defp store_reflection(reflection_text, source_memories, ctx) do
    [first_line | rest] = String.split(reflection_text, "\n", parts: 2)
    summary = String.trim(first_line)
    content = if rest == [], do: reflection_text, else: String.trim(Enum.join(rest, "\n"))

    avg_confidence =
      source_memories
      |> Enum.map(&(&1.confidence || 0.5))
      |> then(&(Enum.sum(&1) / max(length(&1), 1)))

    attrs = %{
      type: "reflection",
      summary: summary,
      content: content,
      importance: 0.8,
      confidence: min(avg_confidence + 0.1, 1.0),
      scope: "private",
      agent_id: ctx.agent_id,
      tenant_id: ctx.tenant_id,
      metadata: %{
        source_memory_ids: Enum.map(source_memories, & &1.id),
        source_count: length(source_memories)
      }
    }

    with {:ok, reflection_memory} <- Storage.store(attrs, ctx) do
      Enum.each(source_memories, fn source ->
        Graph.link(reflection_memory.id, source.id, "supports", [weight: 0.7], ctx)
      end)

      {:ok, reflection_memory}
    end
  end
end
