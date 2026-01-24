defmodule GraphMem.Services.Graph do
  @moduledoc """
  Graph service for memory relationship operations.
  """

  alias GraphMem.{Edge, AccessContext, Backend}

  @doc """
  Creates an edge between two memories.
  """
  @spec link(binary(), binary(), binary(), keyword(), AccessContext.t()) ::
          {:ok, Edge.t()} | {:error, term()}
  def link(from_id, to_id, type \\ "relates_to", opts, %AccessContext{} = ctx) do
    with {:ok, from_memory} <- backend().get_memory(from_id, ctx),
         {:ok, to_memory} <- backend().get_memory(to_id, ctx) do
      scope = Edge.derive_scope(from_memory.scope, to_memory.scope)

      edge_attrs = %{
        from_id: from_id,
        to_id: to_id,
        type: type,
        weight: Keyword.get(opts, :weight, 0.5),
        confidence: Keyword.get(opts, :confidence, 0.7),
        scope: scope,
        metadata: Keyword.get(opts, :metadata, %{})
      }

      with {:ok, edge} <- Edge.new(edge_attrs) do
        backend().put_edge(edge, ctx)
      end
    end
  end

  @doc """
  Gets neighboring memories connected by edges.
  """
  @spec neighbors(binary(), atom(), AccessContext.t(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def neighbors(memory_id, direction \\ :outgoing, %AccessContext{} = ctx, opts \\ []) do
    backend().neighbors(memory_id, direction, ctx, opts)
  end

  @doc """
  Expands the graph from seed memories using depth-limited traversal.
  """
  @spec expand([binary()], AccessContext.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def expand(seed_ids, %AccessContext{} = ctx, opts \\ []) do
    backend().expand(seed_ids, ctx, opts)
  end

  @doc """
  Deletes an edge between two memories.
  """
  @spec unlink(binary(), binary(), binary()) :: :ok | {:error, term()}
  def unlink(from_id, to_id, type \\ "relates_to") do
    backend().delete_edge(from_id, to_id, type)
  end

  defp backend do
    Backend.get_backend()
  end
end
