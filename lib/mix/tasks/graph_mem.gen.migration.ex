if Code.ensure_loaded?(Mix) do
  defmodule Mix.Tasks.GraphMem.Gen.Migration do
    @shortdoc "Generates GraphMem database migrations"

    @moduledoc """
    Generates the database migrations for GraphMem's Postgres backend.

        $ mix graph_mem.gen.migration

    This will create migrations for:
    - `graph_mem_memories` table with pgvector embedding support
    - `graph_mem_edges` table for graph relationships

    ## Options

      * `--repo` - The repo to generate migrations for (defaults to app's repo)
      * `--migrations-path` - The path to generate migrations in

    ## Examples

        $ mix graph_mem.gen.migration
        $ mix graph_mem.gen.migration --repo MyApp.Repo
    """

    use Mix.Task

    import Mix.Generator

    @impl true
    def run(args) do
      unless Code.ensure_loaded?(Ecto) do
        Mix.raise("GraphMem migrations require Ecto. Add {:ecto_sql, \"~> 3.10\"} to your deps.")
      end

      {opts, _, _} = OptionParser.parse(args, switches: [repo: :string, migrations_path: :string])

      repo = get_repo(opts)
      migrations_path = get_migrations_path(opts, repo)

      File.mkdir_p!(migrations_path)

      timestamp = generate_timestamp()

      # Generate memories migration
      memories_file = Path.join(migrations_path, "#{timestamp}_create_graph_mem_memories.exs")
      create_file(memories_file, memories_migration_template())
      Mix.shell().info("Created #{memories_file}")

      # Generate edges migration (1 second later)
      edges_timestamp = increment_timestamp(timestamp)
      edges_file = Path.join(migrations_path, "#{edges_timestamp}_create_graph_mem_edges.exs")
      create_file(edges_file, edges_migration_template())
      Mix.shell().info("Created #{edges_file}")

      Mix.shell().info("""

      Migrations created successfully!

      Next steps:
        1. Ensure pgvector extension is enabled in your database:
           CREATE EXTENSION IF NOT EXISTS vector;

        2. Run the migrations:
           mix ecto.migrate

        3. Configure GraphMem to use the Postgres backend:
           config :graph_mem,
             backend: GraphMem.Backends.Postgres,
             repo: #{inspect(repo)}
      """)
    end

    defp get_repo(opts) do
      case Keyword.get(opts, :repo) do
        nil ->
          app = Mix.Project.config()[:app]

          # Try common repo module names
          candidates = [
            Module.concat([Macro.camelize(to_string(app)), "Repo"]),
            Application.get_env(:graph_mem, :repo)
          ]

          Enum.find(candidates, fn
            nil -> false
            mod -> Code.ensure_loaded?(mod)
          end) || raise_repo_error()

        repo_string ->
          Module.concat([repo_string])
      end
    end

    defp raise_repo_error do
      Mix.raise("""
      Could not determine the Ecto repo.

      Please specify it with --repo:
        mix graph_mem.gen.migration --repo MyApp.Repo
      """)
    end

    defp get_migrations_path(opts, repo) do
      case Keyword.get(opts, :migrations_path) do
        nil ->
          repo_underscore =
            repo
            |> Module.split()
            |> List.last()
            |> Macro.underscore()

          Path.join(["priv", repo_underscore, "migrations"])

        path ->
          path
      end
    end

    defp generate_timestamp do
      {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
      "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
    end

    defp increment_timestamp(timestamp) do
      {seconds, _} = Integer.parse(timestamp)
      to_string(seconds + 1)
    end

    defp pad(i) when i < 10, do: "0#{i}"
    defp pad(i), do: "#{i}"

    defp memories_migration_template do
      """
      defmodule Repo.Migrations.CreateGraphMemMemories do
        use Ecto.Migration

        def change do
          # Ensure pgvector extension is available
          execute "CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector"

          create table(:graph_mem_memories, primary_key: false) do
            add :id, :string, primary_key: true
            add :type, :string, null: false
            add :summary, :string, null: false
            add :content, :text, null: false
            add :embedding, :vector, size: 1536
            add :importance, :float, default: 0.5
            add :confidence, :float, default: 0.7
            add :scope, :string, default: "private"
            add :agent_id, :string, null: false
            add :tenant_id, :string
            add :tags, {:array, :string}, default: []
            add :metadata, :map, default: %{}
            add :session_id, :string
            add :access_count, :integer, default: 0
            add :last_accessed_at, :utc_datetime

            timestamps(type: :utc_datetime)
          end

          create index(:graph_mem_memories, [:type])
          create index(:graph_mem_memories, [:agent_id])
          create index(:graph_mem_memories, [:scope])
          create index(:graph_mem_memories, [:tenant_id])
          create index(:graph_mem_memories, [:session_id])
          create index(:graph_mem_memories, [:confidence])
          create index(:graph_mem_memories, [:agent_id, :scope, :inserted_at])
          create index(:graph_mem_memories, [:tags], using: :gin)

          # Vector similarity search index
          execute \"\"\"
          CREATE INDEX graph_mem_memories_embedding_idx 
          ON graph_mem_memories 
          USING ivfflat (embedding vector_cosine_ops) 
          WITH (lists = 100)
          \"\"\", "DROP INDEX IF EXISTS graph_mem_memories_embedding_idx"
        end
      end
      """
    end

    defp edges_migration_template do
      """
      defmodule Repo.Migrations.CreateGraphMemEdges do
        use Ecto.Migration

        def change do
          create table(:graph_mem_edges, primary_key: false) do
            add :id, :string, primary_key: true
            add :from_memory_id, references(:graph_mem_memories, type: :string, on_delete: :delete_all), null: false
            add :to_memory_id, references(:graph_mem_memories, type: :string, on_delete: :delete_all), null: false
            add :type, :string, null: false, default: "relates_to"
            add :weight, :float, default: 0.5
            add :confidence, :float, default: 0.7
            add :scope, :string, default: "private"
            add :metadata, :map, default: %{}

            timestamps(type: :utc_datetime)
          end

          create index(:graph_mem_edges, [:from_memory_id])
          create index(:graph_mem_edges, [:to_memory_id])
          create index(:graph_mem_edges, [:type])
          create index(:graph_mem_edges, [:scope])
          create index(:graph_mem_edges, [:from_memory_id, :type, :weight])

          create unique_index(:graph_mem_edges, [:from_memory_id, :to_memory_id, :type],
            name: :graph_mem_edges_unique_relationship
          )
        end
      end
      """
    end
  end
end
