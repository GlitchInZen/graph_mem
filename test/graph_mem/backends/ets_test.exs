defmodule GraphMem.Backends.ETSTest do
  use ExUnit.Case

  alias GraphMem.{Memory, Edge, AccessContext}
  alias GraphMem.Backends.ETS, as: ETSBackend

  setup do
    start_supervised!(ETSBackend)
    ctx = AccessContext.new(agent_id: "test_agent")
    {:ok, ctx: ctx}
  end

  describe "put_memory/2 and get_memory/2" do
    test "stores and retrieves a memory", %{ctx: ctx} do
      {:ok, memory} =
        Memory.new(%{
          type: :fact,
          summary: "Test",
          content: "Test content",
          agent_id: ctx.agent_id
        })

      assert {:ok, ^memory} = ETSBackend.put_memory(memory, ctx)
      assert {:ok, retrieved} = ETSBackend.get_memory(memory.id, ctx)
      assert retrieved.id == memory.id
    end

    test "returns :not_found for missing memory", %{ctx: ctx} do
      assert {:error, :not_found} = ETSBackend.get_memory("nonexistent", ctx)
    end

    test "enforces access control", %{ctx: ctx} do
      other_ctx = AccessContext.new(agent_id: "other_agent")

      {:ok, memory} =
        Memory.new(%{
          type: :fact,
          summary: "Private",
          content: "Content",
          agent_id: "other_agent",
          scope: :private
        })

      ETSBackend.put_memory(memory, other_ctx)

      assert {:error, :access_denied} = ETSBackend.get_memory(memory.id, ctx)
    end
  end

  describe "delete_memory/2" do
    test "deletes a memory", %{ctx: ctx} do
      {:ok, memory} =
        Memory.new(%{
          type: :fact,
          summary: "Test",
          content: "Content",
          agent_id: ctx.agent_id
        })

      ETSBackend.put_memory(memory, ctx)
      assert :ok = ETSBackend.delete_memory(memory.id, ctx)
      assert {:error, :not_found} = ETSBackend.get_memory(memory.id, ctx)
    end
  end

  describe "list_memories/2" do
    test "lists accessible memories", %{ctx: ctx} do
      for i <- 1..3 do
        {:ok, mem} =
          Memory.new(%{
            type: :fact,
            summary: "Memory #{i}",
            content: "Content #{i}",
            agent_id: ctx.agent_id
          })

        ETSBackend.put_memory(mem, ctx)
      end

      assert {:ok, memories} = ETSBackend.list_memories(ctx, [])
      assert length(memories) == 3
    end

    test "filters by type", %{ctx: ctx} do
      {:ok, fact} =
        Memory.new(%{type: :fact, summary: "Fact", content: "c", agent_id: ctx.agent_id})

      {:ok, obs} =
        Memory.new(%{type: :observation, summary: "Obs", content: "c", agent_id: ctx.agent_id})

      ETSBackend.put_memory(fact, ctx)
      ETSBackend.put_memory(obs, ctx)

      assert {:ok, memories} = ETSBackend.list_memories(ctx, type: :fact)
      assert length(memories) == 1
      assert hd(memories).type == "fact"
    end
  end

  describe "search_memories/3" do
    test "finds similar memories by embedding", %{ctx: ctx} do
      embedding1 = [1.0, 0.0, 0.0]
      embedding2 = [0.9, 0.1, 0.0]
      embedding3 = [0.0, 1.0, 0.0]

      {:ok, mem1} =
        Memory.new(%{
          type: :fact,
          summary: "Similar 1",
          content: "c",
          agent_id: ctx.agent_id,
          embedding: embedding1
        })

      {:ok, mem2} =
        Memory.new(%{
          type: :fact,
          summary: "Similar 2",
          content: "c",
          agent_id: ctx.agent_id,
          embedding: embedding2
        })

      {:ok, mem3} =
        Memory.new(%{
          type: :fact,
          summary: "Different",
          content: "c",
          agent_id: ctx.agent_id,
          embedding: embedding3
        })

      ETSBackend.put_memory(mem1, ctx)
      ETSBackend.put_memory(mem2, ctx)
      ETSBackend.put_memory(mem3, ctx)

      query = [1.0, 0.0, 0.0]
      assert {:ok, results} = ETSBackend.search_memories(query, ctx, limit: 2, threshold: 0.5)

      assert length(results) == 2
      assert hd(results).memory.summary == "Similar 1"
    end
  end

  describe "put_edge/2 and neighbors/4" do
    test "creates edges and finds neighbors", %{ctx: ctx} do
      {:ok, mem1} =
        Memory.new(%{type: :fact, summary: "A", content: "c", agent_id: ctx.agent_id})

      {:ok, mem2} =
        Memory.new(%{type: :fact, summary: "B", content: "c", agent_id: ctx.agent_id})

      ETSBackend.put_memory(mem1, ctx)
      ETSBackend.put_memory(mem2, ctx)

      {:ok, edge} = Edge.new(%{from_id: mem1.id, to_id: mem2.id, type: "supports"})
      ETSBackend.put_edge(edge, ctx)

      assert {:ok, neighbors} = ETSBackend.neighbors(mem1.id, :outgoing, ctx, [])
      assert length(neighbors) == 1
      assert hd(neighbors).memory.id == mem2.id
      assert hd(neighbors).edge.type == "supports"
    end
  end

  describe "expand/3" do
    test "expands graph from seeds", %{ctx: ctx} do
      {:ok, mem1} =
        Memory.new(%{type: :fact, summary: "A", content: "c", agent_id: ctx.agent_id})

      {:ok, mem2} =
        Memory.new(%{type: :fact, summary: "B", content: "c", agent_id: ctx.agent_id})

      {:ok, mem3} =
        Memory.new(%{type: :fact, summary: "C", content: "c", agent_id: ctx.agent_id})

      ETSBackend.put_memory(mem1, ctx)
      ETSBackend.put_memory(mem2, ctx)
      ETSBackend.put_memory(mem3, ctx)

      {:ok, edge1} = Edge.new(%{from_id: mem1.id, to_id: mem2.id, weight: 0.8})
      {:ok, edge2} = Edge.new(%{from_id: mem2.id, to_id: mem3.id, weight: 0.8})
      ETSBackend.put_edge(edge1, ctx)
      ETSBackend.put_edge(edge2, ctx)

      assert {:ok, result} = ETSBackend.expand([mem1.id], ctx, depth: 2, min_weight: 0.3)
      assert length(result.memories) >= 1
    end

    test "returns empty for no seeds", %{ctx: ctx} do
      assert {:ok, %{memories: [], edges: []}} = ETSBackend.expand([], ctx, [])
    end
  end
end
