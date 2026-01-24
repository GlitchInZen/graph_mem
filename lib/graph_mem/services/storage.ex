defmodule GraphMem.Services.Storage do
  @moduledoc """
  Storage service for memory operations.

  Delegates to the configured backend while handling embedding generation
  and access control validation.
  """

  alias GraphMem.{Memory, AccessContext, Backend, EmbeddingAdapter}

  @doc """
  Stores a memory with optional embedding generation.
  """
  @spec store(map(), AccessContext.t()) :: {:ok, Memory.t()} | {:error, term()}
  def store(attrs, %AccessContext{} = ctx) do
    attrs = apply_access_context(attrs, ctx)

    with {:ok, attrs} <- maybe_generate_embedding(attrs),
         {:ok, memory} <- Memory.new(attrs),
         {:ok, memory} <- validate_write_access(memory, ctx),
         {:ok, memory} <- backend().put_memory(memory, ctx) do
      {:ok, memory}
    end
  end

  @doc """
  Retrieves a memory by ID.
  """
  @spec get(binary(), AccessContext.t()) ::
          {:ok, Memory.t()} | {:error, :not_found | :access_denied}
  def get(memory_id, %AccessContext{} = ctx) do
    backend().get_memory(memory_id, ctx)
  end

  @doc """
  Deletes a memory by ID.
  """
  @spec delete(binary(), AccessContext.t()) :: :ok | {:error, term()}
  def delete(memory_id, %AccessContext{} = ctx) do
    with {:ok, memory} <- get(memory_id, ctx),
         :ok <- validate_delete_access(memory, ctx) do
      backend().delete_memory(memory_id, ctx)
    end
  end

  @doc """
  Lists memories accessible to the context.
  """
  @spec list(AccessContext.t(), keyword()) :: {:ok, [Memory.t()]}
  def list(%AccessContext{} = ctx, opts \\ []) do
    backend().list_memories(ctx, opts)
  end

  # Private

  defp apply_access_context(attrs, %AccessContext{} = ctx) do
    attrs
    |> Map.put_new(:agent_id, ctx.agent_id)
    |> Map.put_new(:tenant_id, ctx.tenant_id)
    |> maybe_restrict_scope(ctx)
  end

  defp maybe_restrict_scope(attrs, %AccessContext{} = ctx) do
    scope = Map.get(attrs, :scope) || "private"

    if AccessContext.can_write?(ctx, scope) do
      attrs
    else
      Map.put(attrs, :scope, "private")
    end
  end

  defp maybe_generate_embedding(attrs) do
    if Map.has_key?(attrs, :embedding) and not is_nil(attrs.embedding) do
      {:ok, attrs}
    else
      content_for_embedding = "#{attrs[:summary]}: #{attrs[:content]}"

      case EmbeddingAdapter.embed(content_for_embedding) do
        {:ok, embedding} ->
          {:ok, Map.put(attrs, :embedding, embedding)}

        {:error, :no_embedding_adapter} ->
          {:ok, attrs}

        {:error, _reason} ->
          {:ok, attrs}
      end
    end
  end

  defp validate_write_access(%Memory{} = memory, %AccessContext{} = ctx) do
    if AccessContext.can_write?(ctx, memory.scope) do
      {:ok, memory}
    else
      {:error, :access_denied}
    end
  end

  defp validate_delete_access(%Memory{} = memory, %AccessContext{} = ctx) do
    cond do
      ctx.role == "system" -> :ok
      memory.agent_id == ctx.agent_id -> :ok
      true -> {:error, :access_denied}
    end
  end

  defp backend do
    Backend.get_backend()
  end
end
