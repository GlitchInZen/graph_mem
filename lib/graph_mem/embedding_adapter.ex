defmodule GraphMem.EmbeddingAdapter do
  @moduledoc """
  Behaviour for embedding adapters.

  Embedding adapters generate vector embeddings from text, enabling
  semantic similarity search. GraphMem ships with adapters for Ollama
  and OpenAI.

  ## Implementing a Custom Adapter

      defmodule MyApp.CustomEmbedding do
        @behaviour GraphMem.EmbeddingAdapter

        @impl true
        def embed(text, opts) do
          # Generate embedding vector
          {:ok, [0.1, 0.2, ...]}
        end

        @impl true
        def dimensions(opts) do
          1536
        end
      end

  Then configure GraphMem to use your adapter:

      config :graph_mem,
        embedding_adapter: MyApp.CustomEmbedding
  """

  @doc """
  Generates an embedding vector for the given text.

  ## Options

  Options are adapter-specific. Common options include:
  - `:model` - The embedding model to use
  - `:endpoint` - API endpoint URL

  ## Returns

  - `{:ok, [float]}` - Embedding vector
  - `{:error, term}` - Error description
  """
  @callback embed(text :: String.t(), opts :: keyword()) ::
              {:ok, [float()]} | {:error, term()}

  @doc """
  Returns the dimensionality of embeddings produced by this adapter.
  """
  @callback dimensions(opts :: keyword()) :: pos_integer()

  @optional_callbacks [dimensions: 1]

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
