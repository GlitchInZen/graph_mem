# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-01-24

### Added

- Initial release
- Core memory structs (`Memory`, `Edge`)
- Access control with `AccessContext`
- Backend behaviour with ETS implementation
- Embedding adapter behaviour with Ollama and OpenAI implementations
- Reflection adapter behaviour
- Agent-facing API: `remember/3`, `recall/3`, `recall_context/3`, `reflect/2`
- Graph operations: `link/5`, `neighbors/4`, `expand/3`
- Memory management: `get_memory/3`, `delete_memory/3`, `list_memories/2`
- Automatic linking of similar memories
- Memory reduction and context formatting for LLM prompts
- Multi-agent isolation with scopes (private/shared/global)
- Multi-tenancy support
