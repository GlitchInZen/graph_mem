# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Web API** - HTTP REST API for external access to memory operations
  - All core operations: create, list, get, delete memories
  - Semantic recall and context endpoints
  - Reflection generation endpoint
  - Graph operations: create edges, get neighbors, expand graph
  - CORS support via `cors_plug`
  - Configurable via `api_enabled` and `api_port` options
- New dependencies: `plug_cowboy`, `plug`, `cors_plug`

## [0.1.0] - 2026-01-25

### Added

- Initial release
- Core memory structs (`Memory`, `Edge`)
- Access control with `AccessContext`
- Centralized configuration via `GraphMem.Config`
- Backend behaviour with pluggable implementations
- **ETS Backend** - In-memory storage (fallback for development)
- **Postgres Backend** - Persistent storage with pgvector (recommended)
  - Efficient vector similarity search via pgvector `<=>` operator
  - Graph expansion via recursive CTEs with parameterized queries
  - Migration generator: `mix graph_mem.gen.migration`
  - Auto-selected when `:repo` is configured
- Embedding adapter behaviour with implementations:
  - **Ollama adapter** (default) - Local embeddings
  - **OpenAI adapter** - Cloud embeddings
  - HTTP timeout and retry configuration
- Reflection adapter behaviour
- Agent-facing API: `remember/3`, `recall/3`, `recall_context/3`, `reflect/2`
- Graph operations: `link/5`, `neighbors/4`, `expand/3`
- Memory management: `get_memory/3`, `delete_memory/3`, `list_memories/2`
- Automatic linking of similar memories
- Memory reduction and context formatting for LLM prompts
- Multi-agent isolation with scopes (private/shared/global)
- Multi-tenancy support
- Confidence-based scope enforcement (low confidence → private)

### Security

- Fixed SQL injection vulnerability in recursive graph traversal
- All Postgres queries now use parameterized statements
