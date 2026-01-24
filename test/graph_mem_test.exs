defmodule GraphMemTest do
  use ExUnit.Case

  setup do
    start_supervised!({GraphMem, []})
    :ok
  end

  describe "remember/3" do
    test "stores a memory" do
      assert {:ok, memory} = GraphMem.remember("agent_1", "Test fact content")
      assert memory.type == "fact"
      assert memory.content == "Test fact content"
      assert memory.agent_id == "agent_1"
    end

    test "accepts options" do
      assert {:ok, memory} =
               GraphMem.remember("agent_1", "Observation content",
                 type: :observation,
                 importance: 0.9,
                 tags: ["test"]
               )

      assert memory.type == "observation"
      assert memory.importance == 0.9
      assert "test" in memory.tags
    end
  end

  describe "get_memory/3" do
    test "retrieves a stored memory" do
      {:ok, memory} = GraphMem.remember("agent_1", "Stored content")
      {:ok, retrieved} = GraphMem.get_memory("agent_1", memory.id)

      assert retrieved.id == memory.id
      assert retrieved.content == "Stored content"
    end

    test "returns error for non-existent memory" do
      assert {:error, :not_found} = GraphMem.get_memory("agent_1", "nonexistent")
    end
  end

  describe "list_memories/2" do
    test "lists all memories for an agent" do
      GraphMem.remember("agent_1", "Memory 1")
      GraphMem.remember("agent_1", "Memory 2")
      GraphMem.remember("agent_2", "Other agent memory")

      {:ok, memories} = GraphMem.list_memories("agent_1")
      assert length(memories) == 2
    end
  end

  describe "delete_memory/3" do
    test "deletes a memory" do
      {:ok, memory} = GraphMem.remember("agent_1", "To delete")
      assert :ok = GraphMem.delete_memory("agent_1", memory.id)
      assert {:error, :not_found} = GraphMem.get_memory("agent_1", memory.id)
    end
  end

  describe "link/5" do
    test "creates edge between memories" do
      {:ok, mem1} = GraphMem.remember("agent_1", "First memory")
      {:ok, mem2} = GraphMem.remember("agent_1", "Second memory")

      assert {:ok, edge} = GraphMem.link("agent_1", mem1.id, mem2.id, "supports", weight: 0.8)
      assert edge.from_id == mem1.id
      assert edge.to_id == mem2.id
      assert edge.type == "supports"
    end
  end

  describe "neighbors/4" do
    test "finds connected memories" do
      {:ok, mem1} = GraphMem.remember("agent_1", "Source")
      {:ok, mem2} = GraphMem.remember("agent_1", "Target")
      GraphMem.link("agent_1", mem1.id, mem2.id, "relates_to", [])

      {:ok, neighbors} = GraphMem.neighbors("agent_1", mem1.id, :outgoing)
      assert length(neighbors) == 1
      assert hd(neighbors).memory.id == mem2.id
    end
  end

  describe "expand/3" do
    test "expands graph from seeds" do
      {:ok, mem1} = GraphMem.remember("agent_1", "A")
      {:ok, mem2} = GraphMem.remember("agent_1", "B")
      {:ok, mem3} = GraphMem.remember("agent_1", "C")

      GraphMem.link("agent_1", mem1.id, mem2.id, "relates_to", weight: 0.8)
      GraphMem.link("agent_1", mem2.id, mem3.id, "relates_to", weight: 0.8)

      {:ok, result} = GraphMem.expand("agent_1", [mem1.id], depth: 2, min_weight: 0.3)
      assert length(result.memories) >= 1
    end
  end
end
