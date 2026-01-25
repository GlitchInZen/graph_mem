if Code.ensure_loaded?(Ecto) do
  defmodule GraphMem.Backends.Postgres.MemorySchema do
    @moduledoc """
    Ecto schema for memories stored in PostgreSQL.
    """

    use Ecto.Schema
    import Ecto.Changeset

    @memory_types ~w(conversation fact episodic reflection observation decision)
    @scopes ~w(private shared global)

    @primary_key {:id, :string, autogenerate: false}

    schema "graph_mem_memories" do
      field(:type, :string)
      field(:summary, :string)
      field(:content, :string)
      field(:embedding, Pgvector.Ecto.Vector)
      field(:importance, :float, default: 0.5)
      field(:confidence, :float, default: 0.7)
      field(:scope, :string, default: "private")
      field(:agent_id, :string)
      field(:tenant_id, :string)
      field(:tags, {:array, :string}, default: [])
      field(:metadata, :map, default: %{})
      field(:session_id, :string)
      field(:access_count, :integer, default: 0)
      field(:last_accessed_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    def changeset(memory, attrs) do
      memory
      |> cast(attrs, [
        :id,
        :type,
        :summary,
        :content,
        :embedding,
        :importance,
        :confidence,
        :scope,
        :agent_id,
        :tenant_id,
        :tags,
        :metadata,
        :session_id,
        :access_count,
        :last_accessed_at,
        :inserted_at,
        :updated_at
      ])
      |> validate_required([:id, :type, :summary, :content, :agent_id])
      |> validate_inclusion(:type, @memory_types)
      |> validate_inclusion(:scope, @scopes)
      |> validate_number(:importance, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
      |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
      |> maybe_enforce_private_scope()
    end

    defp maybe_enforce_private_scope(changeset) do
      confidence = get_field(changeset, :confidence) || 0.7
      scope = get_field(changeset, :scope) || "private"

      if confidence < 0.7 and scope != "private" do
        put_change(changeset, :scope, "private")
      else
        changeset
      end
    end
  end
end
