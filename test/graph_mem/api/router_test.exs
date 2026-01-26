defmodule GraphMem.API.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias GraphMem.API.Router

  @opts Router.init([])

  setup do
    start_supervised!({GraphMem, []})
    :ok
  end

  describe "GET /health" do
    test "returns ok status" do
      conn = conn(:get, "/health") |> Router.call(@opts)

      assert conn.status == 200
      assert %{"status" => "ok"} = Jason.decode!(conn.resp_body)
    end
  end

  describe "POST /api/agents/:agent_id/memories" do
    test "creates a memory" do
      conn =
        conn(:post, "/api/agents/agent_1/memories", %{
          "text" => "Test memory content",
          "type" => "fact"
        })
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 201
      assert %{"data" => data} = Jason.decode!(conn.resp_body)
      assert data["content"] == "Test memory content"
      assert data["type"] == "fact"
      assert data["agent_id"] == "agent_1"
    end

    test "creates memory with all options" do
      conn =
        conn(:post, "/api/agents/agent_1/memories", %{
          "text" => "Important observation",
          "type" => "observation",
          "importance" => 0.9,
          "confidence" => 0.8,
          "tags" => ["test", "api"],
          "metadata" => %{"source" => "test"}
        })
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 201
      assert %{"data" => data} = Jason.decode!(conn.resp_body)
      assert data["type"] == "observation"
      assert data["importance"] == 0.9
      assert data["confidence"] == 0.8
      assert data["tags"] == ["test", "api"]
      assert data["metadata"]["source"] == "test"
    end

    test "returns error when text is missing" do
      conn =
        conn(:post, "/api/agents/agent_1/memories", %{})
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 400
      assert %{"error" => "text is required"} = Jason.decode!(conn.resp_body)
    end
  end

  describe "GET /api/agents/:agent_id/memories" do
    test "lists memories for an agent" do
      create_memory("agent_1", "Memory 1")
      create_memory("agent_1", "Memory 2")
      create_memory("agent_2", "Other agent")

      conn = conn(:get, "/api/agents/agent_1/memories") |> Router.call(@opts)

      assert conn.status == 200
      assert %{"data" => data} = Jason.decode!(conn.resp_body)
      assert length(data) == 2
    end

    test "returns empty list when no memories" do
      conn = conn(:get, "/api/agents/new_agent/memories") |> Router.call(@opts)

      assert conn.status == 200
      assert %{"data" => []} = Jason.decode!(conn.resp_body)
    end
  end

  describe "GET /api/agents/:agent_id/memories/:id" do
    test "returns a memory by id" do
      {:ok, memory} = GraphMem.remember("agent_1", "Test content")

      conn =
        conn(:get, "/api/agents/agent_1/memories/#{memory.id}")
        |> Router.call(@opts)

      assert conn.status == 200
      assert %{"data" => data} = Jason.decode!(conn.resp_body)
      assert data["id"] == memory.id
      assert data["content"] == "Test content"
    end

    test "returns 404 for non-existent memory" do
      conn =
        conn(:get, "/api/agents/agent_1/memories/nonexistent")
        |> Router.call(@opts)

      assert conn.status == 404
      assert %{"error" => "memory not found"} = Jason.decode!(conn.resp_body)
    end
  end

  describe "DELETE /api/agents/:agent_id/memories/:id" do
    test "deletes a memory" do
      {:ok, memory} = GraphMem.remember("agent_1", "To delete")

      conn =
        conn(:delete, "/api/agents/agent_1/memories/#{memory.id}")
        |> Router.call(@opts)

      assert conn.status == 200
      assert %{"data" => %{"deleted" => true}} = Jason.decode!(conn.resp_body)

      assert {:error, :not_found} = GraphMem.get_memory("agent_1", memory.id)
    end

    test "returns 404 for non-existent memory" do
      conn =
        conn(:delete, "/api/agents/agent_1/memories/nonexistent")
        |> Router.call(@opts)

      assert conn.status == 404
    end
  end

  describe "GET /api/agents/:agent_id/memories/recall" do
    test "returns error when query is missing" do
      conn =
        conn(:get, "/api/agents/agent_1/memories/recall")
        |> Router.call(@opts)

      assert conn.status == 400
      assert %{"error" => _} = Jason.decode!(conn.resp_body)
    end

    test "recalls memories with query" do
      create_memory("agent_1", "User prefers dark mode")

      conn =
        conn(:get, "/api/agents/agent_1/memories/recall?q=preferences")
        |> Router.call(@opts)

      assert conn.status == 200
      assert %{"data" => _data} = Jason.decode!(conn.resp_body)
    end
  end

  describe "GET /api/agents/:agent_id/memories/context" do
    test "returns error when query is missing" do
      conn =
        conn(:get, "/api/agents/agent_1/memories/context")
        |> Router.call(@opts)

      assert conn.status == 400
    end

    test "returns context with query" do
      create_memory("agent_1", "Important fact")

      conn =
        conn(:get, "/api/agents/agent_1/memories/context?q=fact")
        |> Router.call(@opts)

      assert conn.status == 200
      assert %{"data" => %{"context" => _}} = Jason.decode!(conn.resp_body)
    end
  end

  describe "POST /api/agents/:agent_id/reflect" do
    test "returns error when insufficient memories" do
      conn =
        conn(:post, "/api/agents/agent_1/reflect", %{"topic" => "test"})
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 422
      assert %{"error" => "insufficient memories for reflection"} = Jason.decode!(conn.resp_body)
    end
  end

  describe "POST /api/agents/:agent_id/edges" do
    test "creates an edge between memories" do
      {:ok, mem1} = GraphMem.remember("agent_1", "First")
      {:ok, mem2} = GraphMem.remember("agent_1", "Second")

      conn =
        conn(:post, "/api/agents/agent_1/edges", %{
          "from_id" => mem1.id,
          "to_id" => mem2.id,
          "type" => "supports",
          "weight" => 0.8
        })
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 201
      assert %{"data" => data} = Jason.decode!(conn.resp_body)
      assert data["from_id"] == mem1.id
      assert data["to_id"] == mem2.id
      assert data["type"] == "supports"
      assert data["weight"] == 0.8
    end

    test "returns error when from_id is missing" do
      conn =
        conn(:post, "/api/agents/agent_1/edges", %{"to_id" => "abc"})
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 400
      assert %{"error" => "from_id is required"} = Jason.decode!(conn.resp_body)
    end

    test "returns error when to_id is missing" do
      conn =
        conn(:post, "/api/agents/agent_1/edges", %{"from_id" => "abc"})
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 400
      assert %{"error" => "to_id is required"} = Jason.decode!(conn.resp_body)
    end
  end

  describe "GET /api/agents/:agent_id/memories/:id/neighbors" do
    test "returns neighbors for a memory" do
      {:ok, mem1} = GraphMem.remember("agent_1", "Source")
      {:ok, mem2} = GraphMem.remember("agent_1", "Target")
      GraphMem.link("agent_1", mem1.id, mem2.id, "relates_to", [])

      conn =
        conn(:get, "/api/agents/agent_1/memories/#{mem1.id}/neighbors")
        |> Router.call(@opts)

      assert conn.status == 200
      assert %{"data" => data} = Jason.decode!(conn.resp_body)
      assert length(data) == 1
      assert hd(data)["memory"]["id"] == mem2.id
    end

    test "supports direction parameter" do
      {:ok, mem1} = GraphMem.remember("agent_1", "Source")
      {:ok, mem2} = GraphMem.remember("agent_1", "Target")
      GraphMem.link("agent_1", mem1.id, mem2.id, "relates_to", [])

      conn =
        conn(:get, "/api/agents/agent_1/memories/#{mem2.id}/neighbors?direction=incoming")
        |> Router.call(@opts)

      assert conn.status == 200
      assert %{"data" => data} = Jason.decode!(conn.resp_body)
      assert length(data) == 1
      assert hd(data)["memory"]["id"] == mem1.id
    end
  end

  describe "POST /api/agents/:agent_id/expand" do
    test "expands graph from seed ids" do
      {:ok, mem1} = GraphMem.remember("agent_1", "A")
      {:ok, mem2} = GraphMem.remember("agent_1", "B")
      GraphMem.link("agent_1", mem1.id, mem2.id, "relates_to", weight: 0.8)

      conn =
        conn(:post, "/api/agents/agent_1/expand", %{
          "seed_ids" => [mem1.id],
          "depth" => 1
        })
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 200
      assert %{"data" => %{"memories" => _, "edges" => _}} = Jason.decode!(conn.resp_body)
    end

    test "returns error when seed_ids is missing" do
      conn =
        conn(:post, "/api/agents/agent_1/expand", %{})
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 400
      assert %{"error" => "seed_ids is required"} = Jason.decode!(conn.resp_body)
    end
  end

  describe "404 handling" do
    test "returns 404 for unknown routes" do
      conn = conn(:get, "/unknown/path") |> Router.call(@opts)

      assert conn.status == 404
      assert %{"error" => "not_found"} = Jason.decode!(conn.resp_body)
    end
  end

  defp create_memory(agent_id, text) do
    {:ok, memory} = GraphMem.remember(agent_id, text)
    memory
  end
end
