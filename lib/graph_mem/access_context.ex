defmodule GraphMem.AccessContext do
  @moduledoc """
  Context struct for memory access control.

  Encapsulates the caller's identity and permissions for memory operations.
  All memory read/write operations require an AccessContext to ensure
  proper isolation and access control.

  ## Usage

      # Create context for a specific agent
      ctx = AccessContext.new(agent_id: "my_agent")

      # Create context with shared access
      ctx = AccessContext.new(
        agent_id: "my_agent",
        tenant_id: "tenant_1",
        allow_shared: true
      )

      # Create system context with full access
      ctx = AccessContext.system()
  """

  @type t :: %__MODULE__{
          agent_id: binary(),
          tenant_id: binary() | nil,
          role: binary(),
          permissions: [binary()],
          allow_shared: boolean(),
          allow_global: boolean()
        }

  @enforce_keys [:agent_id]
  defstruct [
    :agent_id,
    :tenant_id,
    role: "agent",
    permissions: [],
    allow_shared: false,
    allow_global: false
  ]

  @doc """
  Creates a new AccessContext.

  ## Options

  - `:agent_id` - Required. The agent's unique identifier
  - `:tenant_id` - Optional tenant ID for multi-tenancy
  - `:role` - Role: "agent", "supervisor", or "system" (default: "agent")
  - `:permissions` - List of permission strings
  - `:allow_shared` - Can read shared memories (default: false)
  - `:allow_global` - Can read global memories (default: false)
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)

    %__MODULE__{
      agent_id: agent_id,
      tenant_id: Keyword.get(opts, :tenant_id),
      role: Keyword.get(opts, :role, "agent"),
      permissions: Keyword.get(opts, :permissions, []),
      allow_shared: Keyword.get(opts, :allow_shared, false),
      allow_global: Keyword.get(opts, :allow_global, false)
    }
  end

  @doc """
  Creates a system-level AccessContext with full permissions.
  """
  @spec system(keyword()) :: t()
  def system(opts \\ []) do
    %__MODULE__{
      agent_id: Keyword.get(opts, :agent_id, "system"),
      tenant_id: Keyword.get(opts, :tenant_id),
      role: "system",
      permissions: ["read_shared", "write_shared", "read_global", "write_global"],
      allow_shared: true,
      allow_global: true
    }
  end

  @doc """
  Creates a supervisor-level AccessContext with shared access.
  """
  @spec supervisor(binary(), keyword()) :: t()
  def supervisor(agent_id, opts \\ []) do
    %__MODULE__{
      agent_id: agent_id,
      tenant_id: Keyword.get(opts, :tenant_id),
      role: "supervisor",
      permissions: ["read_shared", "write_shared", "read_global"],
      allow_shared: true,
      allow_global: true
    }
  end

  @doc """
  Checks if context can read memories of a given scope.
  """
  @spec can_read?(t(), binary()) :: boolean()
  def can_read?(%__MODULE__{} = ctx, scope) do
    case to_string(scope) do
      "private" ->
        true

      "shared" ->
        ctx.allow_shared or "read_shared" in ctx.permissions or
          ctx.role in ["supervisor", "system"]

      "global" ->
        ctx.allow_global or "read_global" in ctx.permissions or
          ctx.role in ["supervisor", "system"]

      _ ->
        false
    end
  end

  @doc """
  Checks if context can write memories of a given scope.
  """
  @spec can_write?(t(), binary()) :: boolean()
  def can_write?(%__MODULE__{} = ctx, scope) do
    case to_string(scope) do
      "private" -> true
      "shared" -> "write_shared" in ctx.permissions or ctx.role in ["supervisor", "system"]
      "global" -> "write_global" in ctx.permissions or ctx.role == "system"
      _ -> false
    end
  end

  @doc """
  Returns the list of scopes the context can read.
  """
  @spec readable_scopes(t()) :: [binary()]
  def readable_scopes(%__MODULE__{} = ctx) do
    scopes = ["private"]
    scopes = if can_read?(ctx, "shared"), do: scopes ++ ["shared"], else: scopes
    scopes = if can_read?(ctx, "global"), do: scopes ++ ["global"], else: scopes
    scopes
  end

  @doc """
  Checks if the context can access a specific memory based on its scope and owner.
  """
  @spec can_access_memory?(t(), map()) :: boolean()
  def can_access_memory?(%__MODULE__{} = ctx, memory) do
    cond do
      ctx.role == "system" -> true
      memory.scope == "private" and memory.agent_id == ctx.agent_id -> true
      memory.scope == "shared" and can_read?(ctx, "shared") -> check_tenant(ctx, memory)
      memory.scope == "global" and can_read?(ctx, "global") -> true
      true -> false
    end
  end

  defp check_tenant(%{tenant_id: nil}, _memory), do: true

  defp check_tenant(%{tenant_id: tenant_id}, %{tenant_id: memory_tenant}),
    do: tenant_id == memory_tenant

  defp check_tenant(_, _), do: true
end
