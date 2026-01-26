defmodule GraphMem.EmbeddingAdapters.OpenAI do
  @moduledoc """
  OpenAI embedding adapter.

  Generates embeddings using the OpenAI API.

  ## Configuration

      config :graph_mem,
        embedding_adapter: GraphMem.EmbeddingAdapters.OpenAI,
        embedding_model: "text-embedding-3-small",
        openai_api_key: System.get_env("OPENAI_API_KEY"),
        http_timeout: 30_000,
        http_retry: 2

  Or set the `OPENAI_API_KEY` environment variable.

  ## Supported Models

  - `text-embedding-3-small` (1536 dimensions) - Default, cost-effective
  - `text-embedding-3-large` (3072 dimensions) - Higher quality
  - `text-embedding-ada-002` (1536 dimensions) - Legacy model
  """

  @behaviour GraphMem.EmbeddingAdapter

  require Logger

  @default_model "text-embedding-3-small"
  @api_url "https://api.openai.com/v1/embeddings"
  @default_timeout 30_000
  @default_retry 2

  @impl true
  def embed(text, opts \\ []) do
    api_key = get_api_key(opts)
    model = get_model(opts)
    timeout = get_timeout(opts)
    retry = get_retry(opts)

    if is_nil(api_key) or api_key == "" do
      Logger.warning("OpenAI API key not configured")
      {:error, :api_key_not_set}
    else
      body = Jason.encode!(%{model: model, input: text})

      req_opts = [
        body: body,
        headers: [
          {"content-type", "application/json"},
          {"authorization", "Bearer #{api_key}"}
        ],
        receive_timeout: timeout,
        retry: retry_opts(retry)
      ]

      case Req.post(@api_url, req_opts) do
        {:ok, %{status: 200, body: %{"data" => [%{"embedding" => embedding} | _]}}} ->
          {:ok, embedding}

        {:ok, %{status: 429, body: body}} ->
          Logger.warning("OpenAI rate limited: #{inspect(body)}")
          {:error, {:rate_limited, body}}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("OpenAI embedding failed: status=#{status} body=#{inspect(body)}")
          {:error, {:openai_error, status, body}}

        {:error, %Req.TransportError{reason: :timeout}} ->
          Logger.warning("OpenAI embedding timed out after #{timeout}ms")
          {:error, :timeout}

        {:error, reason} ->
          Logger.warning("OpenAI embedding request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end

  @impl true
  def embed_many(texts, opts \\ []) when is_list(texts) do
    api_key = get_api_key(opts)
    model = get_model(opts)
    timeout = get_timeout(opts)
    retry = get_retry(opts)

    if is_nil(api_key) or api_key == "" do
      Logger.warning("OpenAI API key not configured")
      {:error, :api_key_not_set}
    else
      body = Jason.encode!(%{model: model, input: texts})

      req_opts = [
        body: body,
        headers: [
          {"content-type", "application/json"},
          {"authorization", "Bearer #{api_key}"}
        ],
        receive_timeout: timeout,
        retry: retry_opts(retry)
      ]

      case Req.post(@api_url, req_opts) do
        {:ok, %{status: 200, body: %{"data" => data}}} when is_list(data) ->
          # Sort by index to ensure correct ordering (OpenAI may return out of order)
          embeddings =
            data
            |> Enum.sort_by(& &1["index"])
            |> Enum.map(& &1["embedding"])

          if length(embeddings) == length(texts) do
            {:ok, embeddings}
          else
            {:error, {:length_mismatch, expected: length(texts), got: length(embeddings)}}
          end

        {:ok, %{status: 429, body: body}} ->
          Logger.warning("OpenAI rate limited (batch): #{inspect(body)}")
          {:error, {:rate_limited, body}}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("OpenAI batch embedding failed: status=#{status} body=#{inspect(body)}")
          {:error, {:openai_error, status, body}}

        {:error, %Req.TransportError{reason: :timeout}} ->
          Logger.warning("OpenAI batch embedding timed out after #{timeout}ms")
          {:error, :timeout}

        {:error, reason} ->
          Logger.warning("OpenAI batch embedding request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end

  @impl true
  def dimensions(opts \\ []) do
    model = get_model(opts)

    case model do
      "text-embedding-3-small" -> 1536
      "text-embedding-3-large" -> 3072
      "text-embedding-ada-002" -> 1536
      _ -> 1536
    end
  end

  defp get_api_key(opts) do
    Keyword.get(opts, :api_key) ||
      Application.get_env(:graph_mem, :openai_api_key) ||
      System.get_env("OPENAI_API_KEY")
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
