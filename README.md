# GraphMem

[![Hex.pm](https://img.shields.io/hexpm/v/graph_mem.svg)](https://hex.pm/packages/graph_mem)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/graph_mem)

Graph-based long-term memory for AI agents. GraphMem provides persistent memory with automatic relationship discovery, semantic search, and graph-based retrieval.

## Features

- **Semantic memory recall** via vector embeddings
- **Graph-based relationships** between memories  
- **Multi-agent isolation** with scoped sharing (private/shared/global)
- **Pluggable backends** (ETS default, Postgres optional)
- **Pluggable embedding adapters** (Ollama, OpenAI)
- **No heavy dependencies** - works without Phoenix, Ecto, or Oban

## Installation

Add `graph_mem` to your dependencies:

```elixir
def deps do
  [
    {:graph_mem, "~> 0.1.0"}
  ]
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

```elixir
config :graph_mem,
  # Storage backend (default: ETS)
  backend: GraphMem.Backends.ETS,
  
  # Embedding adapter for semantic search
  embedding_adapter: GraphMem.EmbeddingAdapters.Ollama,
  embedding_model: "nomic-embed-text",
  ollama_endpoint: "http://localhost:11434",
  
  # Auto-link similar memories
  auto_link: true,
  link_threshold: 0.75
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

## Pluggable Backends

### ETS Backend (Default)

In-memory storage, suitable for development and small deployments:

```elixir
config :graph_mem,
  backend: GraphMem.Backends.ETS
```

### Custom Backend

Implement `GraphMem.Backend` behaviour:

```elixir
defmodule MyApp.RedisBackend do
  @behaviour GraphMem.Backend
  
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

### OpenAI

```elixir
config :graph_mem,
  embedding_adapter: GraphMem.EmbeddingAdapters.OpenAI,
  embedding_model: "text-embedding-3-small"

# Set OPENAI_API_KEY environment variable
```

### Custom Adapter

```elixir
defmodule MyApp.CustomEmbedding do
  @behaviour GraphMem.EmbeddingAdapter
  
  def embed(text, opts) do
    # Generate embedding
    {:ok, [0.1, 0.2, ...]}
  end
end
```

## Reflection

Generate higher-level insights from memory clusters:

```elixir
# With LLM adapter
config :graph_mem,
  reflection_adapter: MyApp.LLMReflection

{:ok, reflection} = GraphMem.reflect("agent_1", 
  topic: "user preferences",
  min_memories: 5
)
```

## Edge Types

| Type | Description |
|------|-------------|
| `relates_to` | General semantic relationship |
| `supports` | Target reinforces source |
| `contradicts` | Target conflicts with source |
| `causes` | Source leads to target |
| `follows` | Temporal ordering |

## Supervision

Add to your application's supervision tree:

```elixir
def start(_type, _args) do
  children = [
    {GraphMem, []}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

## License

Apache 2.0 License - see LICENSE file.
