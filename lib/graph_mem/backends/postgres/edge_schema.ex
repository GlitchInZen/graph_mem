if Code.ensure_loaded?(Ecto) do
  defmodule GraphMem.Backends.Postgres.EdgeSchema do
    @moduledoc """
    Ecto schema for memory edges stored in PostgreSQL.
    """

    use Ecto.Schema
    import Ecto.Changeset

    alias GraphMem.Backends.Postgres.MemorySchema

    @edge_types ~w(relates_to supports contradicts causes follows)
    @scopes ~w(private shared global)

    @primary_key {:id, :string, autogenerate: false}

    schema "graph_mem_edges" do
      field(:type, :string, default: "relates_to")
      field(:weight, :float, default: 0.5)
      field(:confidence, :float, default: 0.7)
      field(:scope, :string, default: "private")
      field(:metadata, :map, default: %{})

      belongs_to(:from_memory, MemorySchema, type: :string)
      belongs_to(:to_memory, MemorySchema, type: :string)

      timestamps(type: :utc_datetime)
    end

    def changeset(edge, attrs) do
      edge
      |> cast(attrs, [
        :id,
        :from_memory_id,
        :to_memory_id,
        :type,
        :weight,
        :confidence,
        :scope,
        :metadata,
        :inserted_at,
        :updated_at
      ])
      |> validate_required([:id, :from_memory_id, :to_memory_id, :type])
      |> validate_inclusion(:type, @edge_types)
      |> validate_inclusion(:scope, @scopes)
      |> validate_number(:weight, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
      |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
      |> foreign_key_constraint(:from_memory_id)
      |> foreign_key_constraint(:to_memory_id)
      |> unique_constraint([:from_memory_id, :to_memory_id, :type],
        name: :graph_mem_edges_unique_relationship
      )
    end
  end
end
