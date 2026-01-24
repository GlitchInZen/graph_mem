defmodule GraphMem.MemoryTest do
  use ExUnit.Case, async: true

  alias GraphMem.Memory

  describe "new/1" do
    test "creates a memory with required fields" do
      attrs = %{
        type: :fact,
        summary: "Test summary",
        content: "Test content",
        agent_id: "agent_1"
      }

      assert {:ok, memory} = Memory.new(attrs)
      assert memory.type == "fact"
      assert memory.summary == "Test summary"
      assert memory.content == "Test content"
      assert memory.agent_id == "agent_1"
      assert memory.scope == "private"
      assert memory.importance == 0.5
      assert memory.confidence == 0.7
      assert is_binary(memory.id)
    end

    test "validates memory type" do
      attrs = %{type: :invalid, summary: "s", content: "c", agent_id: "a"}
      assert {:error, {:invalid_type, :invalid}} = Memory.new(attrs)
    end

    test "validates scope" do
      attrs = %{type: :fact, summary: "s", content: "c", agent_id: "a", scope: :invalid}
      assert {:error, {:invalid_scope, :invalid}} = Memory.new(attrs)
    end

    test "requires summary, content, and agent_id" do
      assert {:error, {:missing_fields, _}} = Memory.new(%{type: :fact})
    end

    test "demotes low confidence memories to private scope" do
      attrs = %{
        type: :fact,
        summary: "s",
        content: "c",
        agent_id: "a",
        confidence: 0.5,
        scope: :shared
      }

      assert {:ok, memory} = Memory.new(attrs)
      assert memory.scope == "private"
    end

    test "allows shared scope with high confidence" do
      attrs = %{
        type: :fact,
        summary: "s",
        content: "c",
        agent_id: "a",
        confidence: 0.8,
        scope: :shared
      }

      assert {:ok, memory} = Memory.new(attrs)
      assert memory.scope == "shared"
    end
  end

  describe "memory_types/0" do
    test "returns valid types" do
      types = Memory.memory_types()
      assert "fact" in types
      assert "conversation" in types
      assert "reflection" in types
    end
  end

  describe "touch/1" do
    test "increments access count" do
      {:ok, memory} = Memory.new(%{type: :fact, summary: "s", content: "c", agent_id: "a"})
      touched = Memory.touch(memory)

      assert touched.access_count == 1
      assert %DateTime{} = touched.last_accessed_at
    end
  end
end
