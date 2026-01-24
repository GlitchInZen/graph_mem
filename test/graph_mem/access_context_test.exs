defmodule GraphMem.AccessContextTest do
  use ExUnit.Case, async: true

  alias GraphMem.AccessContext

  describe "new/1" do
    test "creates context with required fields" do
      ctx = AccessContext.new(agent_id: "agent_1")

      assert ctx.agent_id == "agent_1"
      assert ctx.role == "agent"
      assert ctx.allow_shared == false
      assert ctx.allow_global == false
    end

    test "accepts optional fields" do
      ctx =
        AccessContext.new(
          agent_id: "agent_1",
          tenant_id: "tenant_1",
          allow_shared: true,
          permissions: ["read_shared"]
        )

      assert ctx.tenant_id == "tenant_1"
      assert ctx.allow_shared == true
      assert "read_shared" in ctx.permissions
    end
  end

  describe "system/1" do
    test "creates system context with full access" do
      ctx = AccessContext.system()

      assert ctx.role == "system"
      assert ctx.allow_shared == true
      assert ctx.allow_global == true
      assert "write_global" in ctx.permissions
    end
  end

  describe "supervisor/2" do
    test "creates supervisor context with shared access" do
      ctx = AccessContext.supervisor("agent_1")

      assert ctx.agent_id == "agent_1"
      assert ctx.role == "supervisor"
      assert ctx.allow_shared == true
      assert "read_shared" in ctx.permissions
    end
  end

  describe "can_read?/2" do
    test "all contexts can read private" do
      ctx = AccessContext.new(agent_id: "a")
      assert AccessContext.can_read?(ctx, "private")
    end

    test "requires allow_shared for shared scope" do
      ctx = AccessContext.new(agent_id: "a")
      refute AccessContext.can_read?(ctx, "shared")

      ctx_shared = AccessContext.new(agent_id: "a", allow_shared: true)
      assert AccessContext.can_read?(ctx_shared, "shared")
    end

    test "requires allow_global for global scope" do
      ctx = AccessContext.new(agent_id: "a")
      refute AccessContext.can_read?(ctx, "global")

      ctx_global = AccessContext.new(agent_id: "a", allow_global: true)
      assert AccessContext.can_read?(ctx_global, "global")
    end

    test "supervisor can read shared and global" do
      ctx = AccessContext.supervisor("a")
      assert AccessContext.can_read?(ctx, "shared")
      assert AccessContext.can_read?(ctx, "global")
    end
  end

  describe "can_write?/2" do
    test "all contexts can write private" do
      ctx = AccessContext.new(agent_id: "a")
      assert AccessContext.can_write?(ctx, "private")
    end

    test "requires write_shared permission for shared" do
      ctx = AccessContext.new(agent_id: "a", allow_shared: true)
      refute AccessContext.can_write?(ctx, "shared")

      ctx_write = AccessContext.new(agent_id: "a", permissions: ["write_shared"])
      assert AccessContext.can_write?(ctx_write, "shared")
    end

    test "requires write_global permission for global" do
      ctx = AccessContext.supervisor("a")
      refute AccessContext.can_write?(ctx, "global")

      ctx_system = AccessContext.system()
      assert AccessContext.can_write?(ctx_system, "global")
    end
  end

  describe "readable_scopes/1" do
    test "returns only private for basic agent" do
      ctx = AccessContext.new(agent_id: "a")
      assert AccessContext.readable_scopes(ctx) == ["private"]
    end

    test "returns all scopes for system" do
      ctx = AccessContext.system()
      scopes = AccessContext.readable_scopes(ctx)
      assert "private" in scopes
      assert "shared" in scopes
      assert "global" in scopes
    end
  end

  describe "can_access_memory?/2" do
    test "agent can access own private memory" do
      ctx = AccessContext.new(agent_id: "agent_1")
      memory = %{scope: "private", agent_id: "agent_1"}

      assert AccessContext.can_access_memory?(ctx, memory)
    end

    test "agent cannot access other agent's private memory" do
      ctx = AccessContext.new(agent_id: "agent_1")
      memory = %{scope: "private", agent_id: "agent_2"}

      refute AccessContext.can_access_memory?(ctx, memory)
    end

    test "system can access any memory" do
      ctx = AccessContext.system()
      memory = %{scope: "private", agent_id: "other"}

      assert AccessContext.can_access_memory?(ctx, memory)
    end
  end
end
