defmodule GraphMem.EmbeddingAdapters.Ollama do
  @moduledoc """
  Ollama embedding adapter.

  Generates embeddings using a local Ollama instance. This is the default
  embedding adapter for GraphMem.

  ## Configuration

      config :graph_mem,
        embedding_adapter: GraphMem.EmbeddingAdapters.Ollama,
        ollama_endpoint: "http://localhost:11434",
        embedding_model: "nomic-embed-text",
        http_timeout: 30_000,
        http_retry: 2

  ## Supported Models

  - `nomic-embed-text` (768 dimensions) - Default, good balance of quality/speed
  - `mxbai-embed-large` (1024 dimensions) - Higher quality, slower
  - `all-minilm` (384 dimensions) - Fastest, lower quality
  - `snowflake-arctic-embed` (1024 dimensions) - High quality
  """

  @behaviour GraphMem.EmbeddingAdapter

  require Logger

  @default_endpoint "http://localhost:11434"
  @default_model "nomic-embed-text"
  @default_timeout 30_000
  @default_retry 2

  @impl true
  def embed(text, opts \\ []) do
    endpoint = get_endpoint(opts)
    model = get_model(opts)
    timeout = get_timeout(opts)
    retry = get_retry(opts)

    url = "#{endpoint}/api/embed"
    body = Jason.encode!(%{model: model, input: text})

    req_opts = [
      body: body,
      headers: [{"content-type", "application/json"}],
      receive_timeout: timeout,
      retry: retry_opts(retry)
    ]

    case Req.post(url, req_opts) do
      {:ok, %{status: 200, body: %{"embeddings" => [embedding | _]}}} ->
        {:ok, embedding}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Ollama embedding failed: status=#{status} body=#{inspect(body)}")
        {:error, {:ollama_error, status, body}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        Logger.warning("Ollama embedding timed out after #{timeout}ms")
        {:error, :timeout}

      {:error, reason} ->
        Logger.warning("Ollama embedding request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def embed_many(texts, opts \\ []) when is_list(texts) do
    endpoint = get_endpoint(opts)
    model = get_model(opts)
    timeout = get_timeout(opts)
    retry = get_retry(opts)

    url = "#{endpoint}/api/embed"
    body = Jason.encode!(%{model: model, input: texts})

    req_opts = [
      body: body,
      headers: [{"content-type", "application/json"}],
      receive_timeout: timeout,
      retry: retry_opts(retry)
    ]

    case Req.post(url, req_opts) do
      {:ok, %{status: 200, body: %{"embeddings" => embeddings}}} when is_list(embeddings) ->
        {:ok, embeddings}

      {:ok, %{status: 400, body: _body}} ->
        # Ollama may not support batch; fall back to sequential
        embed_many_sequential(texts, opts)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Ollama batch embedding failed: status=#{status} body=#{inspect(body)}")
        {:error, {:ollama_error, status, body}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        Logger.warning("Ollama batch embedding timed out after #{timeout}ms")
        {:error, :timeout}

      {:error, reason} ->
        Logger.warning("Ollama batch embedding request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp embed_many_sequential(texts, opts) do
    Enum.reduce_while(texts, {:ok, []}, fn text, {:ok, acc} ->
      case embed(text, opts) do
        {:ok, emb} -> {:cont, {:ok, [emb | acc]}}
        {:error, err} -> {:halt, {:error, err}}
      end
    end)
    |> case do
      {:ok, embs} -> {:ok, Enum.reverse(embs)}
      {:error, err} -> {:error, err}
    end
  end

  @impl true
  def dimensions(opts \\ []) do
    model = get_model(opts)

    case model do
      "nomic-embed-text" -> 768
      "mxbai-embed-large" -> 1024
      "all-minilm" -> 384
      "snowflake-arctic-embed" -> 1024
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

  defp get_timeout(opts) do
    Keyword.get(opts, :timeout) ||
      Application.get_env(:graph_mem, :http_timeout, @default_timeout)
  end

  defp get_retry(opts) do
    Keyword.get(opts, :retry) ||
      Application.get_env(:graph_mem, :http_retry, @default_retry)
  end

  defp retry_opts(0), do: false
  defp retry_opts(_count), do: :safe_transient
end
