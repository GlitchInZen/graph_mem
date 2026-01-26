defmodule GraphMem.EmbeddingAdapter do
  @moduledoc """
  Behaviour for embedding adapters.

  ...existing docs...
  """

  @callback embed(text :: String.t(), opts :: keyword()) ::
              {:ok, [float()]} | {:error, term()}

  @callback dimensions(opts :: keyword()) :: pos_integer()

  # New optional callback: batched embeddings
  @callback embed_many(texts :: [String.t()], opts :: keyword()) ::
              {:ok, [[float()]]} | {:error, term()}

  @optional_callbacks [dimensions: 1, embed_many: 2]

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Generates an embedding using the configured adapter.
  """
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(text, opts \\ []) do
    adapter = get_adapter()

    if adapter do
      adapter.embed(text, opts)
    else
      {:error, :no_embedding_adapter}
    end
  end

  @doc """
  Generates embeddings for many texts using the configured adapter.

  Default implementation: if the adapter implements `embed_many/2`, call it;
  otherwise fall back to calling `embed/2` per item (sequential).
  """
  @spec embed_many([String.t()], keyword()) :: {:ok, [[float()]]} | {:error, term()}
  def embed_many(texts, opts \\ []) when is_list(texts) do
    adapter = get_adapter()

    cond do
      adapter == nil ->
        {:error, :no_embedding_adapter}

      function_exported?(adapter, :embed_many, 2) ->
        adapter.embed_many(texts, opts)

      true ->
        # fallback: sequential embeds
        results =
          Enum.map(texts, fn t ->
            case adapter.embed(t, opts) do
              {:ok, emb} -> {:ok, emb}
              {:error, err} -> {:error, err}
            end
          end)

        if Enum.all?(results, &match?({:ok, _}, &1)) do
          {:ok, Enum.map(results, fn {:ok, e} -> e end)}
        else
          {:error, {:partial_failure, results}}
        end
    end
  end

  @doc """
  Generates an embedding, returning nil on failure instead of an error.
  """
  @spec embed_or_nil(String.t(), keyword()) :: [float()] | nil
  def embed_or_nil(text, opts \\ []) do
    case embed(text, opts) do
      {:ok, embedding} -> embedding
      _ -> nil
    end
  end

  @doc """
  Returns the currently configured embedding adapter.
  """
  @spec get_adapter() :: module() | nil
  def get_adapter do
    GraphMem.Config.embedding_adapter()
  end

  @doc """
  Computes cosine similarity between two vectors.
  """
  @spec cosine_similarity([float()], [float()]) :: float()
  def cosine_similarity(v1, v2) when length(v1) == length(v2) do
    dot_product = Enum.zip(v1, v2) |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)
    magnitude1 = :math.sqrt(Enum.reduce(v1, 0.0, fn x, acc -> acc + x * x end))
    magnitude2 = :math.sqrt(Enum.reduce(v2, 0.0, fn x, acc -> acc + x * x end))

    if magnitude1 == 0.0 or magnitude2 == 0.0 do
      0.0
    else
      dot_product / (magnitude1 * magnitude2)
    end
  end

  def cosine_similarity(_, _), do: 0.0
end