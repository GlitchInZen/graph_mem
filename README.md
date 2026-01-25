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
  http_retry: 2
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

  @impl true
  def dimensions(_opts), do: 768
end
```

## Edge Types

| Type | Description |
|------|-------------|
| `relates_to` | General semantic relationship (default) |
| `supports` | Target reinforces source |
| `contradicts` | Target conflicts with source |
| `causes` | Source leads to target |
| `follows` | Temporal ordering |

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

## Similarity Scoring

GraphMem uses cosine similarity for semantic search. Scores range from -1 to 1, where:
- 1.0 = identical meaning
- 0.0 = unrelated
- -1.0 = opposite meaning

In practice, most normalized embeddings produce scores between 0 and 1.

The default `threshold` is 0.3, meaning results with similarity below 0.3 are filtered out.

## Error Handling

GraphMem gracefully handles embedding failures:
- If the embedding adapter fails, memories are stored without embeddings
- Semantic search will skip memories without embeddings
- Warnings are logged for debugging

Configure timeouts and retries:

```elixir
config :graph_mem,
  http_timeout: 30_000,  # 30 seconds
  http_retry: 2          # 2 retry attempts
```

## Roadmap

- **0.1** - Core API, ETS backend, Ollama/OpenAI adapters
- **0.2** - PostgreSQL backend, migrations, graph expansion
- **0.3** - Reflection adapters, memory consolidation
- **0.4** - Telemetry, distributed support
- **1.0** - Stable API

## License

MIT License - see [LICENSE](LICENSE) file.
