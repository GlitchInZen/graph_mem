defmodule GraphMem.EmbeddingAdapters.Ollama do
  @moduledoc """
  Ollama embedding adapter.

  Generates embeddings using a local Ollama instance.

  ## Configuration

      config :graph_mem,
        embedding_adapter: GraphMem.EmbeddingAdapters.Ollama,
        ollama_endpoint: "http://localhost:11434",
        embedding_model: "nomic-embed-text"
  """

  @behaviour GraphMem.EmbeddingAdapter

  @default_endpoint "http://localhost:11434"
  @default_model "nomic-embed-text"

  @impl true
  def embed(text, opts \\ []) do
    endpoint = get_endpoint(opts)
    model = get_model(opts)

    url = "#{endpoint}/api/embed"
    body = Jason.encode!(%{model: model, input: text})

    headers = [{"content-type", "application/json"}]

    case Req.post(url, body: body, headers: headers) do
      {:ok, %{status: 200, body: %{"embeddings" => [embedding | _]}}} ->
        {:ok, embedding}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ollama_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def dimensions(opts \\ []) do
    model = get_model(opts)

    case model do
      "nomic-embed-text" -> 768
      "mxbai-embed-large" -> 1024
      "all-minilm" -> 384
      _ -> 768
    end
  end

  defp get_endpoint(opts) do
    Keyword.get(opts, :endpoint) ||
      Application.get_env(:graph_mem, :ollama_endpoint, @default_endpoint)
  end

  defp get_model(opts) do
    Keyword.get(opts, :model) ||
      Application.get_env(:graph_mem, :embedding_model, @default_model)
  end
end
