defmodule GraphMem.EdgeTest do
  use ExUnit.Case, async: true

  alias GraphMem.Edge

  describe "new/1" do
    test "creates an edge with required fields" do
      attrs = %{from_id: "mem_1", to_id: "mem_2"}

      assert {:ok, edge} = Edge.new(attrs)
      assert edge.from_id == "mem_1"
      assert edge.to_id == "mem_2"
      assert edge.type == "relates_to"
      assert edge.weight == 0.5
      assert is_binary(edge.id)
    end

    test "accepts all edge types" do
      for type <- Edge.edge_types() do
        attrs = %{from_id: "a", to_id: "b", type: type}
        assert {:ok, edge} = Edge.new(attrs)
        assert edge.type == type
      end
    end

    test "validates edge type" do
      attrs = %{from_id: "a", to_id: "b", type: "invalid"}
      assert {:error, {:invalid_type, "invalid"}} = Edge.new(attrs)
    end

    test "requires from_id and to_id" do
      assert {:error, {:missing_fields, _}} = Edge.new(%{})
    end
  end

  describe "derive_scope/2" do
    test "returns more restrictive scope" do
      assert Edge.derive_scope("private", "shared") == "private"
      assert Edge.derive_scope("shared", "private") == "private"
      assert Edge.derive_scope("shared", "global") == "shared"
      assert Edge.derive_scope("global", "global") == "global"
    end
  end

  describe "edge_types/0" do
    test "returns valid types" do
      types = Edge.edge_types()
      assert "relates_to" in types
      assert "supports" in types
      assert "contradicts" in types
      assert "causes" in types
      assert "follows" in types
    end
  end
end
