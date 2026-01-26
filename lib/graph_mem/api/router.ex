defmodule GraphMem.API.Router do
  @moduledoc """
  HTTP API router for GraphMem.

  Provides REST endpoints for memory operations.
  """

  use Plug.Router

  alias GraphMem.API.{MemoryController, GraphController}

  plug Plug.Logger
  plug CORSPlug
  plug :match

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason

  plug :dispatch

  # Health check
  get "/health" do
    send_json(conn, 200, %{status: "ok"})
  end

  # Memory endpoints
  post "/api/agents/:agent_id/memories" do
    MemoryController.create(conn, conn.params)
  end

  get "/api/agents/:agent_id/memories" do
    MemoryController.index(conn, conn.params)
  end

  get "/api/agents/:agent_id/memories/recall" do
    MemoryController.recall(conn, conn.params)
  end

  get "/api/agents/:agent_id/memories/context" do
    MemoryController.recall_context(conn, conn.params)
  end

  get "/api/agents/:agent_id/memories/:id" do
    MemoryController.show(conn, conn.params)
  end

  delete "/api/agents/:agent_id/memories/:id" do
    MemoryController.delete(conn, conn.params)
  end

  # Reflection endpoint
  post "/api/agents/:agent_id/reflect" do
    MemoryController.reflect(conn, conn.params)
  end

  # Graph endpoints
  post "/api/agents/:agent_id/edges" do
    GraphController.create_edge(conn, conn.params)
  end

  get "/api/agents/:agent_id/memories/:id/neighbors" do
    GraphController.neighbors(conn, conn.params)
  end

  post "/api/agents/:agent_id/expand" do
    GraphController.expand(conn, conn.params)
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
