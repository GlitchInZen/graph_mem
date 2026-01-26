# GraphMem

[![Hex.pm](https://img.shields.io/hexpm/v/graph_mem.svg)](https://hex.pm/packages/graph_mem)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/graph_mem)
[![CI](https://github.com/noemaex/graph_mem/workflows/CI/badge.svg)](https://github.com/noemaex/graph_mem/actions)

Graph-based long-term memory for AI agents. GraphMem provides persistent memory with automatic relationship discovery, semantic search, and graph-based retrieval.

## Features

- **Semantic memory recall** via vector embeddings (cosine similarity)
- **Graph-based relationships** between memories with typed edges
- **Multi-agent isolation** with scoped sharing (private/shared/global)
- **Pluggable backends** - PostgreSQL (recommended) or ETS (development)
- **Pluggable embedding adapters** - Ollama (default) or OpenAI
- **Automatic memory linking** based on semantic similarity
- **No heavy dependencies** - works with or without Phoenix/Ecto

## Installation

Add `graph_mem` to your dependencies:

```elixir
def deps do
  [
    {:graph_mem, "~> 0.1.0"},

    # For PostgreSQL backend (recommended for production)
    {:ecto_sql, "~> 3.10"},
    {:postgrex, "~> 0.17"},
    {:pgvector, "~> 0.3"}
  ]
end
```

### Minimal Installation (ETS only)

For development or small-scale use without PostgreSQL:

```elixir
def deps do
  [{:graph_mem, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
# Start GraphMem (add to your supervision tree)
GraphMem.start_link()

# Store a memory
{:ok, memory} = GraphMem.remember("agent_1", "Paris is the capital of France")

# Recall relevant memories
{:ok, results} = GraphMem.recall("agent_1", "What is the capital of France?")

# Generate a reflection from related memories
{:ok, reflection} = GraphMem.reflect("agent_1", topic: "geography")
```

## Configuration

### PostgreSQL Backend (Recommended)

```elixir
config :graph_mem,
  # Storage backend - Postgres is auto-selected when :repo is configured
  repo: MyApp.Repo,

  # Embedding configuration (Ollama is the default)
  embedding_adapter: GraphMem.EmbeddingAdapters.Ollama,
  embedding_model: "nomic-embed-text",
  ollama_endpoint: "http://localhost:11434",

  # Auto-link similar memories
  auto_link: true,
  link_threshold: 0.75,

  # HTTP client settings
  http_timeout: 30_000,
  http_retry: 2,

  # Async embedding settings
  batch_timeout_ms: 50,    # Max wait before flushing batch
  batch_size: 32           # Max batch size before flush
```

#### PostgreSQL Setup

1. Enable pgvector extension:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

2. Generate and run migrations:

```bash
mix graph_mem.gen.migration
mix ecto.migrate
```

### ETS Backend (Development)

For development or when PostgreSQL is not available, GraphMem automatically falls back to ETS:

```elixir
config :graph_mem,
  backend: GraphMem.Backends.ETS,
  embedding_adapter: GraphMem.EmbeddingAdapters.Ollama
```

**Note:** ETS storage is in-memory only and does not persist across restarts.

### OpenAI Embeddings

```elixir
config :graph_mem,
  embedding_adapter: GraphMem.EmbeddingAdapters.OpenAI,
  embedding_model: "text-embedding-3-small",
  openai_api_key: System.get_env("OPENAI_API_KEY")
```

## Core API

### Storing Memories

```elixir
# Simple fact
GraphMem.remember("agent_1", "User prefers dark mode")

# With options
GraphMem.remember("agent_1", "Deploy v1.2 caused errors",
  type: :observation,
  importance: 0.8,
  confidence: 0.9,
  scope: :shared,
  tags: ["deploy", "incident"]
)
```

### Recalling Memories

```elixir
# Basic recall
{:ok, results} = GraphMem.recall("agent_1", "user preferences")

# With filtering and graph expansion
{:ok, results} = GraphMem.recall("agent_1", "deployment issues",
  limit: 10,
  type: :observation,
  tags: ["deploy"],
  expand_graph: true,
  graph_depth: 2
)

# Get formatted context for LLM prompts
{:ok, context} = GraphMem.recall_context("agent_1", "recent events",
  format: :structured,
  max_tokens: 2000
)
```

### Graph Operations

```elixir
# Link memories
GraphMem.link("agent_1", mem1_id, mem2_id, "supports", weight: 0.8)

# Get neighbors
{:ok, neighbors} = GraphMem.neighbors("agent_1", memory_id, :outgoing)

# Expand from seeds
{:ok, graph} = GraphMem.expand("agent_1", [seed_id], depth: 2)
```

## Memory Types

| Type | Description | Default Importance |
|------|-------------|-------------------|
| `fact` | Learned facts about users or domain | 0.6 |
| `conversation` | Key points from chat sessions | 0.5 |
| `episodic` | Specific events or interactions | 0.5 |
| `reflection` | Synthesized insights | 0.8 |
| `observation` | Runtime observations | 0.5 |
| `decision` | Recorded decisions and rationale | 0.7 |

## Access Control

### Scopes

| Scope | Description |
|-------|-------------|
| `private` | Only the owning agent (default) |
| `shared` | Agents in the same tenant |
| `global` | All agents |

### Multi-Agent Usage

```elixir
# Agent 1 stores shared observation
GraphMem.remember("infra_agent", "High CPU usage detected",
  scope: :shared,
  tenant_id: "team_a"
)

# Agent 2 can recall it (with permission)
{:ok, results} = GraphMem.recall("planning_agent", "system health",
  allow_shared: true,
  tenant_id: "team_a"
)
```

### Confidence-Based Filtering

Memories with confidence below 0.7 are automatically demoted to `private` scope, preventing low-confidence information from polluting shared memory.

## Pluggable Backends

### ETS Backend (Default Fallback)

In-memory storage, suitable for development:

```elixir
config :graph_mem,
  backend: GraphMem.Backends.ETS
```

### PostgreSQL Backend (Recommended)

Persistent storage with pgvector for efficient similarity search:

```elixir
config :graph_mem,
  backend: GraphMem.Backends.Postgres,
  repo: MyApp.Repo
```

Features:
- Efficient vector similarity search via pgvector `<=>` operator
- Graph expansion via recursive CTEs
- Full index support for fast queries
- Persistent storage across restarts

### Custom Backend

Implement the `GraphMem.Backend` behaviour:

```elixir
defmodule MyApp.CustomBackend do
  @behaviour GraphMem.Backend

  def start_link(opts), do: ...
  def put_memory(memory, ctx), do: ...
  def get_memory(id, ctx), do: ...
  def search_memories(embedding, ctx, opts), do: ...
  # ... other callbacks
end
```

## Embedding Adapters

### Ollama (Default)

```elixir
config :graph_mem,
  embedding_adapter: GraphMem.EmbeddingAdapters.Ollama,
  ollama_endpoint: "http://localhost:11434",
  embedding_model: "nomic-embed-text"
```

Supported models:
- `nomic-embed-text` (768 dimensions) - Default
- `mxbai-embed-large` (1024 dimensions)
- `all-minilm` (384 dimensions)
- `snowflake-arctic-embed` (1024 dimensions)

### OpenAI

```elixir
config :graph_mem,
  embedding_adapter: GraphMem.EmbeddingAdapters.OpenAI,
  embedding_model: "text-embedding-3-small"
```

Supported models:
- `text-embedding-3-small` (1536 dimensions) - Default
- `text-embedding-3-large` (3072 dimensions)
- `text-embedding-ada-002` (1536 dimensions)

### Custom Adapter

```elixir
defmodule MyApp.CustomEmbedding do
  @behaviour GraphMem.EmbeddingAdapter

  @impl true
  def embed(text, opts) do
    {:ok, [0.1, 0.2, ...]}
  end

  # Optional: batch embedding for efficiency
  @impl true
  def embed_many(texts, opts) do
    {:ok, Enum.map(texts, fn _ -> [0.1, 0.2, ...] end)}
  end

  @impl true
  def dimensions(_opts), do: 768
end
```

**Note:** If `embed_many/2` is not implemented, GraphMem falls back to sequential `embed/2` calls.

## Edge Types

| Type | Description |
|------|-------------|
| `relates_to` | General semantic relationship (default) |
| `supports` | Target reinforces source |
| `contradicts` | Target conflicts with source |
| `causes` | Source leads to target |
| `follows` | Temporal ordering |

## Async Embedding

GraphMem computes embeddings asynchronously after storing memories. This keeps `remember/3` fast and non-blocking.

### How It Works

1. `remember/3` stores the memory immediately (without embedding)
2. An async task computes the embedding via the batching system
3. The embedding is persisted to the backend
4. Auto-linking is triggered after the embedding exists

### Batching

Embedding requests are batched for efficiency. Configure batch behavior:

```elixir
config :graph_mem,
  batch_timeout_ms: 50,  # Flush batch after 50ms of inactivity
  batch_size: 32         # Flush when batch reaches 32 requests
```

### Oban Integration (Optional)

For durable job processing with retries, configure Oban:

```elixir
config :graph_mem,
  use_oban: true,
  task_supervisor: GraphMem.TaskSupervisor  # fallback if Oban unavailable
```

Then define the worker module:

```elixir
defmodule GraphMem.Workers.EmbeddingIndexJob do
  use Oban.Worker, queue: :embeddings, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"memory_id" => memory_id, "agent_id" => agent_id}}) do
    ctx = GraphMem.AccessContext.new(agent_id: agent_id)

    case GraphMem.get_memory(agent_id, memory_id) do
      {:ok, memory} -> GraphMem.Embedding.Indexer.do_index(memory, ctx)
      {:error, :not_found} -> :ok  # Memory was deleted
    end
  end
end
```

Without Oban, GraphMem uses `Task.Supervisor` for fire-and-forget background tasks.

## Supervision

Add to your application's supervision tree:

```elixir
def start(_type, _args) do
  children = [
    MyApp.Repo,
    {GraphMem, []}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

## Web API

GraphMem includes an optional HTTP API for accessing memory operations from external services.

### Configuration

```elixir
config :graph_mem,
  api_enabled: true,
  api_port: 4000
```

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Health check |
| `POST` | `/api/agents/:agent_id/memories` | Create a memory |
| `GET` | `/api/agents/:agent_id/memories` | List memories |
| `GET` | `/api/agents/:agent_id/memories/:id` | Get a memory |
| `DELETE` | `/api/agents/:agent_id/memories/:id` | Delete a memory |
| `GET` | `/api/agents/:agent_id/memories/recall?q=...` | Semantic recall |
| `GET` | `/api/agents/:agent_id/memories/context?q=...` | Recall formatted for LLM |
| `POST` | `/api/agents/:agent_id/reflect` | Generate a reflection |
| `POST` | `/api/agents/:agent_id/edges` | Create an edge |
| `GET` | `/api/agents/:agent_id/memories/:id/neighbors` | Get graph neighbors |
| `POST` | `/api/agents/:agent_id/expand` | Expand graph from seeds |

### Examples

#### Create a memory

```bash
curl -X POST http://localhost:4000/api/agents/agent_1/memories \
  -H "Content-Type: application/json" \
  -d '{"text": "User prefers dark mode", "type": "fact", "importance": 0.7}'
```

#### Recall memories

```bash
curl "http://localhost:4000/api/agents/agent_1/memories/recall?q=user+preferences&limit=5"
```

#### Create an edge

```bash
curl -X POST http://localhost:4000/api/agents/agent_1/edges \
  -H "Content-Type: application/json" \
  -d '{"from_id": "abc123", "to_id": "def456", "type": "supports", "weight": 0.8}'
```

#### Generate a reflection

```bash
curl -X POST http://localhost:4000/api/agents/agent_1/reflect \
  -H "Content-Type: application/json" \
  -d '{"topic": "user preferences", "min_memories": 3}'
```

### Response Format

All responses are JSON. Successful responses wrap data in a `data` key:

```json
{"data": {"id": "abc123", "type": "fact", ...}}
```

Errors return an `error` key:

```json
{"error": "memory not found"}
```

### Query Parameters

Memory recall endpoints support these query parameters:

| Parameter | Type | Description |
|-----------|------|-------------|
| `q` | string | Search query (required for recall) |
| `limit` | integer | Max results (default: 5) |
| `threshold` | float | Min similarity score (default: 0.3) |
| `type` | string | Filter by memory type |
| `tags` | array | Filter by tags |
| `expand_graph` | boolean | Include graph-connected memories |
| `graph_depth` | integer | Expansion depth (default: 1) |
| `allow_shared` | boolean | Include shared memories |
| `allow_global` | boolean | Include global memories |
| `tenant_id` | string | Tenant for multi-tenancy |

## Similarity Scoring

GraphMem uses cosine similarity for semantic search. Scores range from -1 to 1, where:
- 1.0 = identical meaning
- 0.0 = unrelated
- -1.0 = opposite meaning

In practice, most normalized embeddings produce scores between 0 and 1.

The default `threshold` is 0.3, meaning results with similarity below 0.3 are filtered out.

## Error Handling

GraphMem gracefully handles embedding failures:
- Memories are stored immediately; embeddings are computed asynchronously
- If async embedding fails, warnings are logged but the memory remains
- Semantic search will skip memories without embeddings
- Batch failures are logged; individual requests receive error responses

Configure timeouts and retries:

```elixir
config :graph_mem,
  http_timeout: 30_000,  # 30 seconds
  http_retry: 2          # 2 retry attempts
```

## License

Apache 2.0 License - see [LICENSE](LICENSE) file.
