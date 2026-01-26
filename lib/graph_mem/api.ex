defmodule GraphMem.API do
  @moduledoc """
  Web API for GraphMem.

  ## Configuration

      config :graph_mem,
        api_enabled: true,
        api_port: 4000

  ## Endpoints

  ### Health Check

      GET /health

  ### Memories

      POST   /api/agents/:agent_id/memories           - Create a memory
      GET    /api/agents/:agent_id/memories           - List memories
      GET    /api/agents/:agent_id/memories/:id       - Get a memory
      DELETE /api/agents/:agent_id/memories/:id       - Delete a memory
      GET    /api/agents/:agent_id/memories/recall    - Recall memories by query
      GET    /api/agents/:agent_id/memories/context   - Recall formatted context

  ### Reflection

      POST /api/agents/:agent_id/reflect              - Generate a reflection

  ### Graph

      POST /api/agents/:agent_id/edges                - Create an edge
      GET  /api/agents/:agent_id/memories/:id/neighbors - Get neighbors
      POST /api/agents/:agent_id/expand               - Expand graph from seeds

  ## Request/Response Format

  All endpoints accept and return JSON. Responses are wrapped in a `data` key:

      {"data": {...}}

  Errors return an `error` key:

      {"error": "message"}

  ## Examples

  ### Create a memory

      POST /api/agents/agent_1/memories
      Content-Type: application/json

      {
        "text": "User prefers dark mode",
        "type": "fact",
        "importance": 0.7,
        "tags": ["preferences", "ui"]
      }

  ### Recall memories

      GET /api/agents/agent_1/memories/recall?q=user+preferences&limit=5

  ### Create an edge

      POST /api/agents/agent_1/edges
      Content-Type: application/json

      {
        "from_id": "abc123",
        "to_id": "def456",
        "type": "supports",
        "weight": 0.8
      }
  """
end
