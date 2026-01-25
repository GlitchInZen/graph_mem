if Code.ensure_loaded?(Ecto) do
  defmodule GraphMem.Backends.Postgres do
    @moduledoc """
    PostgreSQL-based storage backend using Ecto and pgvector.

    This backend provides persistent storage with efficient vector similarity
    search via pgvector's `<=>` operator and graph traversal via recursive CTEs.

    ## Requirements

    - PostgreSQL with pgvector extension
    - Ecto, Postgrex, and Pgvector dependencies
    - A configured Ecto Repo

    ## Configuration

        config :graph_mem,
          backend: GraphMem.Backends.Postgres,
          repo: MyApp.Repo

    ## Setup

    1. Add dependencies to mix.exs:

        {:ecto_sql, "~> 3.10"},
        {:postgrex, "~> 0.17"},
        {:pgvector, "~> 0.3"}

    2. Run migrations:

        mix graph_mem.gen.migration
        mix ecto.migrate

    ## Features

    - Efficient vector similarity search via pgvector
    - Graph expansion via recursive CTEs
    - Full access control enforcement
    - Automatic scope filtering in queries
    """

    @behaviour GraphMem.Backend

    use GenServer

    import Ecto.Query

    alias GraphMem.{Memory, Edge, AccessContext}
    alias GraphMem.Backends.Postgres.{MemorySchema, EdgeSchema}

    # ============================================================================
    # Lifecycle
    # ============================================================================

    @impl GraphMem.Backend
    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl GraphMem.Backend
    def child_spec(opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [opts]},
        type: :worker
      }
    end

    @impl GenServer
    def init(opts) do
      repo = Keyword.get(opts, :repo) || get_repo()

      unless repo do
        raise ArgumentError, """
        GraphMem.Backends.Postgres requires a repo to be configured.

        Add to your config:

            config :graph_mem,
              backend: GraphMem.Backends.Postgres,
              repo: MyApp.Repo
        """
      end

      {:ok, %{repo: repo}}
    end

    # ============================================================================
    # Memory Operations
    # ============================================================================

    @impl GraphMem.Backend
    def put_memory(%Memory{} = memory, %AccessContext{} = _ctx) do
      repo = get_repo()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        id: memory.id,
        type: memory.type,
        summary: memory.summary,
        content: memory.content,
        embedding: memory.embedding && Pgvector.new(memory.embedding),
        importance: memory.importance,
        confidence: memory.confidence,
        scope: memory.scope,
        agent_id: memory.agent_id,
        tenant_id: memory.tenant_id,
        tags: memory.tags || [],
        metadata: memory.metadata || %{},
        session_id: memory.session_id,
        access_count: memory.access_count || 0,
        last_accessed_at: memory.last_accessed_at,
        inserted_at: memory.inserted_at || now,
        updated_at: now
      }

      changeset = MemorySchema.changeset(%MemorySchema{}, attrs)

      case repo.insert(changeset, on_conflict: :replace_all, conflict_target: :id) do
        {:ok, schema} ->
          {:ok, schema_to_memory(schema)}

        {:error, changeset} ->
          {:error, changeset}
      end
    end

    @impl GraphMem.Backend
    def get_memory(id, %AccessContext{} = ctx) do
      repo = get_repo()

      case repo.get(MemorySchema, id) do
        nil ->
          {:error, :not_found}

        schema ->
          memory = schema_to_memory(schema)

          if AccessContext.can_access_memory?(ctx, memory) do
            {:ok, memory}
          else
            {:error, :access_denied}
          end
      end
    end

    @impl GraphMem.Backend
    def delete_memory(id, %AccessContext{} = _ctx) do
      repo = get_repo()

      repo.transaction(fn ->
        from(e in EdgeSchema, where: e.from_memory_id == ^id or e.to_memory_id == ^id)
        |> repo.delete_all()

        case repo.get(MemorySchema, id) do
          nil -> :ok
          schema -> repo.delete(schema)
        end
      end)

      :ok
    end

    @impl GraphMem.Backend
    def list_memories(%AccessContext{} = ctx, opts) do
      repo = get_repo()
      limit = Keyword.get(opts, :limit, 100)
      type = Keyword.get(opts, :type)
      tags = Keyword.get(opts, :tags)

      memories =
        MemorySchema
        |> apply_scope_filter(ctx)
        |> maybe_filter_type(type)
        |> maybe_filter_tags(tags)
        |> order_by(desc: :inserted_at)
        |> limit(^limit)
        |> repo.all()
        |> Enum.map(&schema_to_memory/1)

      {:ok, memories}
    end

    # ============================================================================
    # Semantic Search
    # ============================================================================

    @impl GraphMem.Backend
    def search_memories(query_embedding, %AccessContext{} = ctx, opts) do
      repo = get_repo()
      limit = Keyword.get(opts, :limit, 5)
      threshold = Keyword.get(opts, :threshold, 0.3)
      type = Keyword.get(opts, :type)
      tags = Keyword.get(opts, :tags)
      min_confidence = Keyword.get(opts, :min_confidence, 0.5)

      query_vector = Pgvector.new(query_embedding)

      results =
        MemorySchema
        |> where([m], not is_nil(m.embedding))
        |> where([m], m.confidence >= ^min_confidence)
        |> apply_scope_filter(ctx)
        |> maybe_filter_type(type)
        |> maybe_filter_tags(tags)
        |> select([m], %{
          memory: m,
          score:
            fragment(
              "1 - (? <=> ?::vector)",
              m.embedding,
              ^query_vector
            )
        })
        |> order_by([m], fragment("? <=> ?::vector", m.embedding, ^query_vector))
        |> limit(^limit)
        |> repo.all()
        |> Enum.filter(&(&1.score >= threshold))
        |> Enum.map(fn %{memory: schema, score: score} ->
          %{memory: schema_to_memory(schema), score: score}
        end)

      update_access_counts(results, repo)

      {:ok, results}
    end

    # ============================================================================
    # Edge Operations
    # ============================================================================

    @impl GraphMem.Backend
    def put_edge(%Edge{} = edge, %AccessContext{} = _ctx) do
      repo = get_repo()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        id: edge.id,
        from_memory_id: edge.from_id,
        to_memory_id: edge.to_id,
        type: edge.type,
        weight: edge.weight,
        confidence: edge.confidence,
        scope: edge.scope,
        metadata: edge.metadata || %{},
        inserted_at: edge.inserted_at || now,
        updated_at: now
      }

      changeset = EdgeSchema.changeset(%EdgeSchema{}, attrs)

      case repo.insert(changeset, on_conflict: :nothing) do
        {:ok, schema} ->
          {:ok, schema_to_edge(schema)}

        {:error, changeset} ->
          {:error, changeset}
      end
    end

    @impl GraphMem.Backend
    def neighbors(memory_id, direction, %AccessContext{} = ctx, opts) do
      repo = get_repo()
      type = Keyword.get(opts, :type)
      min_weight = Keyword.get(opts, :min_weight, 0.0)
      limit = Keyword.get(opts, :limit, 50)

      query =
        case direction do
          :outgoing ->
            from(e in EdgeSchema,
              join: m in MemorySchema,
              on: e.to_memory_id == m.id,
              where: e.from_memory_id == ^memory_id,
              select: %{memory: m, edge: e}
            )

          :incoming ->
            from(e in EdgeSchema,
              join: m in MemorySchema,
              on: e.from_memory_id == m.id,
              where: e.to_memory_id == ^memory_id,
              select: %{memory: m, edge: e}
            )

          :both ->
            outgoing =
              from(e in EdgeSchema,
                join: m in MemorySchema,
                on: e.to_memory_id == m.id,
                where: e.from_memory_id == ^memory_id,
                select: %{memory: m, edge: e}
              )

            incoming =
              from(e in EdgeSchema,
                join: m in MemorySchema,
                on: e.from_memory_id == m.id,
                where: e.to_memory_id == ^memory_id,
                select: %{memory: m, edge: e}
              )

            union_all(outgoing, ^incoming)
        end

      results =
        query
        |> maybe_filter_edge_type(type)
        |> where([e, m], e.weight >= ^min_weight)
        |> apply_memory_scope_filter(ctx)
        |> limit(^limit)
        |> repo.all()
        |> Enum.map(fn %{memory: m, edge: e} ->
          %{memory: schema_to_memory(m), edge: schema_to_edge(e)}
        end)

      {:ok, results}
    end

    @impl GraphMem.Backend
    def expand(seed_ids, %AccessContext{} = ctx, opts) do
      repo = get_repo()
      depth = min(Keyword.get(opts, :depth, 2), 3)
      min_weight = Keyword.get(opts, :min_weight, 0.3)
      min_confidence = Keyword.get(opts, :min_confidence, 0.5)
      limit = Keyword.get(opts, :limit, 50)

      if Enum.empty?(seed_ids) do
        {:ok, %{memories: [], edges: []}}
      else
        {memories, edges} =
          traverse_graph(seed_ids, depth, min_weight, min_confidence, limit, ctx, repo)

        {:ok, %{memories: memories, edges: edges}}
      end
    end

    @impl GraphMem.Backend
    def delete_edge(from_id, to_id, type) do
      repo = get_repo()

      from(e in EdgeSchema,
        where:
          e.from_memory_id == ^from_id and
            e.to_memory_id == ^to_id and
            e.type == ^type
      )
      |> repo.delete_all()

      :ok
    end

    # ============================================================================
    # Private Helpers
    # ============================================================================

    defp get_repo do
      Application.get_env(:graph_mem, :repo)
    end

    defp schema_to_memory(%MemorySchema{} = schema) do
      embedding =
        case schema.embedding do
          nil -> nil
          %Pgvector{} = v -> Pgvector.to_list(v)
          list when is_list(list) -> list
        end

      %Memory{
        id: schema.id,
        type: schema.type,
        summary: schema.summary,
        content: schema.content,
        embedding: embedding,
        importance: schema.importance,
        confidence: schema.confidence,
        scope: schema.scope,
        agent_id: schema.agent_id,
        tenant_id: schema.tenant_id,
        tags: schema.tags || [],
        metadata: schema.metadata || %{},
        session_id: schema.session_id,
        access_count: schema.access_count || 0,
        last_accessed_at: schema.last_accessed_at,
        inserted_at: schema.inserted_at,
        updated_at: schema.updated_at
      }
    end

    defp schema_to_edge(%EdgeSchema{} = schema) do
      %Edge{
        id: schema.id,
        from_id: schema.from_memory_id,
        to_id: schema.to_memory_id,
        type: schema.type,
        weight: schema.weight,
        confidence: schema.confidence,
        scope: schema.scope,
        metadata: schema.metadata || %{},
        inserted_at: schema.inserted_at
      }
    end

    defp apply_scope_filter(query, %AccessContext{} = ctx) do
      cond do
        ctx.role == "system" ->
          query

        AccessContext.can_read?(ctx, "global") and AccessContext.can_read?(ctx, "shared") ->
          if ctx.tenant_id do
            where(
              query,
              [m],
              (m.scope == "private" and m.agent_id == ^ctx.agent_id) or
                (m.scope == "shared" and m.tenant_id == ^ctx.tenant_id) or
                m.scope == "global"
            )
          else
            where(
              query,
              [m],
              (m.scope == "private" and m.agent_id == ^ctx.agent_id) or
                m.scope in ["shared", "global"]
            )
          end

        AccessContext.can_read?(ctx, "shared") ->
          if ctx.tenant_id do
            where(
              query,
              [m],
              (m.scope == "private" and m.agent_id == ^ctx.agent_id) or
                (m.scope == "shared" and m.tenant_id == ^ctx.tenant_id)
            )
          else
            where(
              query,
              [m],
              (m.scope == "private" and m.agent_id == ^ctx.agent_id) or
                m.scope == "shared"
            )
          end

        true ->
          where(query, [m], m.scope == "private" and m.agent_id == ^ctx.agent_id)
      end
    end

    defp apply_memory_scope_filter(query, %AccessContext{} = ctx) do
      scopes = AccessContext.readable_scopes(ctx)

      where(query, [_e, m], m.scope in ^scopes)
      |> where([_e, m], m.scope != "private" or m.agent_id == ^ctx.agent_id)
    end

    defp maybe_filter_type(query, nil), do: query
    defp maybe_filter_type(query, type), do: where(query, [m], m.type == ^to_string(type))

    defp maybe_filter_tags(query, nil), do: query
    defp maybe_filter_tags(query, []), do: query

    defp maybe_filter_tags(query, tags) when is_list(tags) do
      where(query, [m], fragment("? && ?", m.tags, ^tags))
    end

    defp maybe_filter_edge_type(query, nil), do: query

    defp maybe_filter_edge_type(query, type),
      do: where(query, [e, _m], e.type == ^to_string(type))

    defp update_access_counts(results, repo) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Enum.each(results, fn %{memory: memory} ->
        from(m in MemorySchema, where: m.id == ^memory.id)
        |> repo.update_all(inc: [access_count: 1], set: [last_accessed_at: now])
      end)
    end

    defp traverse_graph(seed_ids, depth, min_weight, min_confidence, limit, ctx, repo) do
      scope_conditions = build_scope_conditions(ctx)

      query = """
      WITH RECURSIVE graph_traversal AS (
        -- Base case: seed memories
        SELECT m.id, m.type, m.summary, m.content, m.importance, m.confidence,
               m.scope, m.agent_id, m.tenant_id, m.tags, m.metadata, m.embedding,
               m.session_id, m.access_count, m.last_accessed_at,
               m.inserted_at, m.updated_at,
               0 as depth, ARRAY[m.id] as path
        FROM graph_mem_memories m
        WHERE m.id = ANY($1)
          AND m.confidence >= $4
          #{scope_conditions}

        UNION ALL

        -- Recursive case: follow edges
        SELECT m.id, m.type, m.summary, m.content, m.importance, m.confidence,
               m.scope, m.agent_id, m.tenant_id, m.tags, m.metadata, m.embedding,
               m.session_id, m.access_count, m.last_accessed_at,
               m.inserted_at, m.updated_at,
               gt.depth + 1, gt.path || m.id
        FROM graph_traversal gt
        JOIN graph_mem_edges e ON e.from_memory_id = gt.id
        JOIN graph_mem_memories m ON m.id = e.to_memory_id
        WHERE gt.depth < $2
          AND e.weight >= $3
          AND m.confidence >= $4
          AND NOT (m.id = ANY(gt.path))
          #{scope_conditions}
      )
      SELECT DISTINCT ON (id) *
      FROM graph_traversal
      ORDER BY id, depth
      LIMIT $5
      """

      {:ok, result} = repo.query(query, [seed_ids, depth, min_weight, min_confidence, limit])

      memories = parse_memory_rows(result.rows, result.columns)

      memory_ids = Enum.map(memories, & &1.id)

      edges =
        if length(memory_ids) > 1 do
          from(e in EdgeSchema,
            where: e.from_memory_id in ^memory_ids and e.to_memory_id in ^memory_ids,
            where: e.weight >= ^min_weight
          )
          |> repo.all()
          |> Enum.map(&schema_to_edge/1)
        else
          []
        end

      {memories, edges}
    end

    defp build_scope_conditions(%AccessContext{} = ctx) do
      conditions = ["(m.scope = 'private' AND m.agent_id = '#{ctx.agent_id}')"]

      conditions =
        if AccessContext.can_read?(ctx, "shared") do
          tenant_clause =
            if ctx.tenant_id do
              " AND m.tenant_id = '#{ctx.tenant_id}'"
            else
              ""
            end

          conditions ++ ["(m.scope = 'shared'#{tenant_clause})"]
        else
          conditions
        end

      conditions =
        if AccessContext.can_read?(ctx, "global") do
          conditions ++ ["(m.scope = 'global')"]
        else
          conditions
        end

      "AND (" <> Enum.join(conditions, " OR ") <> ")"
    end

    defp parse_memory_rows(rows, columns) do
      col_map = Enum.with_index(columns) |> Map.new()

      Enum.map(rows, fn row ->
        embedding =
          case Enum.at(row, col_map["embedding"]) do
            nil -> nil
            %Pgvector{} = v -> Pgvector.to_list(v)
            list when is_list(list) -> list
            _ -> nil
          end

        %Memory{
          id: Enum.at(row, col_map["id"]),
          type: Enum.at(row, col_map["type"]),
          summary: Enum.at(row, col_map["summary"]),
          content: Enum.at(row, col_map["content"]),
          embedding: embedding,
          importance: Enum.at(row, col_map["importance"]),
          confidence: Enum.at(row, col_map["confidence"]),
          scope: Enum.at(row, col_map["scope"]),
          agent_id: Enum.at(row, col_map["agent_id"]),
          tenant_id: Enum.at(row, col_map["tenant_id"]),
          tags: Enum.at(row, col_map["tags"]) || [],
          metadata: Enum.at(row, col_map["metadata"]) || %{},
          session_id: Enum.at(row, col_map["session_id"]),
          access_count: Enum.at(row, col_map["access_count"]) || 0,
          last_accessed_at: Enum.at(row, col_map["last_accessed_at"]),
          inserted_at: Enum.at(row, col_map["inserted_at"]),
          updated_at: Enum.at(row, col_map["updated_at"])
        }
      end)
    end
  end
end
