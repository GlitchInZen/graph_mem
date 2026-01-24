defmodule GraphMem.Edge do
  @moduledoc """
  Edge struct representing a relationship between two memories.

  Edges enable graph-based memory traversal and reasoning. They connect
  memory atoms with typed, weighted relationships.

  ## Edge Types

  - `"relates_to"` - General semantic relationship (default)
  - `"supports"` - Target memory supports/reinforces source
  - `"contradicts"` - Target memory conflicts with source
  - `"causes"` - Source memory causes/leads to target
  - `"follows"` - Temporal ordering (source happens before target)

  ## Scopes

  Edge scope is typically derived from the more restrictive of the
  two connected memories. A private-to-shared edge inherits "private" scope.
  """

  @edge_types ~w(relates_to supports contradicts causes follows)
  @scopes ~w(private shared global)

  @type t :: %__MODULE__{
          id: binary(),
          from_id: binary(),
          to_id: binary(),
          type: binary(),
          weight: float(),
          confidence: float(),
          scope: binary(),
          metadata: map(),
          inserted_at: DateTime.t() | nil
        }

  @enforce_keys [:id, :from_id, :to_id, :type]
  defstruct [
    :id,
    :from_id,
    :to_id,
    :inserted_at,
    type: "relates_to",
    weight: 0.5,
    confidence: 0.7,
    scope: "private",
    metadata: %{}
  ]

  @doc """
  Creates a new Edge struct.

  ## Required Fields

  - `:from_id` - Source memory ID
  - `:to_id` - Target memory ID

  ## Optional Fields

  - `:id` - Edge ID (auto-generated if not provided)
  - `:type` - Edge type (default: "relates_to")
  - `:weight` - Relationship strength 0.0-1.0 (default: 0.5)
  - `:confidence` - Edge reliability 0.0-1.0 (default: 0.7)
  - `:scope` - Access scope (default: "private")
  - `:metadata` - Additional data
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs),
         :ok <- validate_type(attrs),
         :ok <- validate_scope(attrs) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      edge = %__MODULE__{
        id: Map.get(attrs, :id) || generate_id(),
        from_id: Map.fetch!(attrs, :from_id),
        to_id: Map.fetch!(attrs, :to_id),
        type: to_string(Map.get(attrs, :type, "relates_to")),
        weight: Map.get(attrs, :weight, 0.5),
        confidence: Map.get(attrs, :confidence, 0.7),
        scope: to_string(Map.get(attrs, :scope, "private")),
        metadata: Map.get(attrs, :metadata, %{}),
        inserted_at: Map.get(attrs, :inserted_at, now)
      }

      {:ok, edge}
    end
  end

  @doc """
  Creates a new Edge struct, raising on error.
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, edge} -> edge
      {:error, reason} -> raise ArgumentError, "Invalid edge: #{inspect(reason)}"
    end
  end

  @doc """
  Returns the list of valid edge types.
  """
  def edge_types, do: @edge_types

  @doc """
  Returns the list of valid scopes.
  """
  def scopes, do: @scopes

  @doc """
  Validates that an edge type is valid.
  """
  def valid_type?(type) when is_atom(type), do: to_string(type) in @edge_types
  def valid_type?(type) when is_binary(type), do: type in @edge_types
  def valid_type?(_), do: false

  @doc """
  Derives the scope for an edge based on the connected memories.

  The edge scope is the more restrictive of the two memory scopes.
  """
  @spec derive_scope(binary(), binary()) :: binary()
  def derive_scope(scope1, scope2) do
    priority = %{"private" => 0, "shared" => 1, "global" => 2}
    if priority[scope1] <= priority[scope2], do: scope1, else: scope2
  end

  # Private

  defp validate_required(attrs) do
    required = [:from_id, :to_id]
    missing = Enum.filter(required, &is_nil(Map.get(attrs, &1)))

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end

  defp validate_type(attrs) do
    type = Map.get(attrs, :type, "relates_to")

    if valid_type?(type) do
      :ok
    else
      {:error, {:invalid_type, type}}
    end
  end

  defp validate_scope(attrs) do
    scope = Map.get(attrs, :scope, "private")

    if scope in @scopes or to_string(scope) in @scopes do
      :ok
    else
      {:error, {:invalid_scope, scope}}
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
