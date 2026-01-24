defmodule GraphMem.Memory do
  @moduledoc """
  Memory struct representing a single memory atom.

  Memories store information that persists across sessions and can be
  recalled based on semantic similarity.

  ## Types

  - `:fact` - Learned facts about users or domain knowledge
  - `:conversation` - Key points from chat sessions
  - `:episodic` - Specific events or interactions
  - `:reflection` - Higher-level insights synthesized from other memories
  - `:observation` - Runtime observations from agent activity
  - `:decision` - Recorded decisions and their rationale

  ## Scopes

  - `:private` - Only accessible by the owning agent (default)
  - `:shared` - Accessible by agents in the same tenant
  - `:global` - Accessible by all agents
  """

  @memory_types ~w(conversation fact episodic reflection observation decision)
  @scopes ~w(private shared global)

  @type t :: %__MODULE__{
          id: binary(),
          type: binary(),
          summary: binary(),
          content: binary(),
          embedding: [float()] | nil,
          importance: float(),
          confidence: float(),
          scope: binary(),
          agent_id: binary(),
          tenant_id: binary() | nil,
          tags: [binary()],
          metadata: map(),
          session_id: binary() | nil,
          access_count: non_neg_integer(),
          last_accessed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:id, :type, :summary, :content, :agent_id, :scope]
  defstruct [
    :id,
    :type,
    :summary,
    :content,
    :embedding,
    :agent_id,
    :tenant_id,
    :session_id,
    :last_accessed_at,
    :inserted_at,
    :updated_at,
    importance: 0.5,
    confidence: 0.7,
    scope: "private",
    tags: [],
    metadata: %{},
    access_count: 0
  ]

  @doc """
  Creates a new Memory struct.

  ## Required Fields

  - `:type` - One of the valid memory types
  - `:summary` - Brief summary of the memory
  - `:content` - Full content of the memory
  - `:agent_id` - ID of the owning agent

  ## Optional Fields

  - `:id` - Memory ID (auto-generated if not provided)
  - `:importance` - Score from 0.0 to 1.0 (default: 0.5)
  - `:confidence` - Reliability score 0.0 to 1.0 (default: 0.7)
  - `:scope` - Access scope (default: "private")
  - `:embedding` - Vector embedding for similarity search
  - `:tenant_id` - Tenant for multi-tenancy
  - `:tags` - List of tags for filtering
  - `:metadata` - Additional structured data
  - `:session_id` - Associated chat session ID
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_type(attrs),
         :ok <- validate_scope(attrs),
         :ok <- validate_required(attrs) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      memory = %__MODULE__{
        id: Map.get(attrs, :id) || generate_id(),
        type: to_string(Map.fetch!(attrs, :type)),
        summary: Map.fetch!(attrs, :summary),
        content: Map.fetch!(attrs, :content),
        embedding: Map.get(attrs, :embedding),
        importance: Map.get(attrs, :importance, 0.5),
        confidence: Map.get(attrs, :confidence, 0.7),
        scope:
          normalize_scope(Map.get(attrs, :scope, "private"), Map.get(attrs, :confidence, 0.7)),
        agent_id: Map.fetch!(attrs, :agent_id),
        tenant_id: Map.get(attrs, :tenant_id),
        tags: Map.get(attrs, :tags, []),
        metadata: Map.get(attrs, :metadata, %{}),
        session_id: Map.get(attrs, :session_id),
        access_count: Map.get(attrs, :access_count, 0),
        last_accessed_at: Map.get(attrs, :last_accessed_at),
        inserted_at: Map.get(attrs, :inserted_at, now),
        updated_at: Map.get(attrs, :updated_at, now)
      }

      {:ok, memory}
    end
  end

  @doc """
  Creates a new Memory struct, raising on error.
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, memory} -> memory
      {:error, reason} -> raise ArgumentError, "Invalid memory: #{inspect(reason)}"
    end
  end

  @doc """
  Returns the list of valid memory types.
  """
  def memory_types, do: @memory_types

  @doc """
  Returns the list of valid scopes.
  """
  def scopes, do: @scopes

  @doc """
  Validates that a type is valid.
  """
  def valid_type?(type) when is_atom(type), do: to_string(type) in @memory_types
  def valid_type?(type) when is_binary(type), do: type in @memory_types
  def valid_type?(_), do: false

  @doc """
  Validates that a scope is valid.
  """
  def valid_scope?(scope) when is_atom(scope), do: to_string(scope) in @scopes
  def valid_scope?(scope) when is_binary(scope), do: scope in @scopes
  def valid_scope?(_), do: false

  @doc """
  Updates a memory's access metadata (count and timestamp).
  """
  @spec touch(t()) :: t()
  def touch(%__MODULE__{} = memory) do
    %{memory | access_count: memory.access_count + 1, last_accessed_at: DateTime.utc_now()}
  end

  # Private

  defp validate_type(attrs) do
    type = Map.get(attrs, :type)

    cond do
      is_nil(type) -> {:error, {:missing_field, :type}}
      valid_type?(type) -> :ok
      true -> {:error, {:invalid_type, type}}
    end
  end

  defp validate_scope(attrs) do
    scope = Map.get(attrs, :scope, "private")

    if valid_scope?(scope) do
      :ok
    else
      {:error, {:invalid_scope, scope}}
    end
  end

  defp validate_required(attrs) do
    required = [:summary, :content, :agent_id]

    missing = Enum.filter(required, &is_nil(Map.get(attrs, &1)))

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end

  defp normalize_scope(scope, confidence) do
    scope_string = to_string(scope)

    if confidence < 0.7 and scope_string != "private" do
      "private"
    else
      scope_string
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
