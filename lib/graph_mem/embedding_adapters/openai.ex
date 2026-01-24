defmodule GraphMem.EmbeddingAdapters.OpenAI do
  @moduledoc """
  OpenAI embedding adapter.

  Generates embeddings using the OpenAI API.

  ## Configuration

      config :graph_mem,
        embedding_adapter: GraphMem.EmbeddingAdapters.OpenAI,
        embedding_model: "text-embedding-3-small"

  Requires the `OPENAI_API_KEY` environment variable to be set.
  """

  @behaviour GraphMem.EmbeddingAdapter

  @default_model "text-embedding-3-small"
  @api_url "https://api.openai.com/v1/embeddings"

  @impl true
  def embed(text, opts \\ []) do
    api_key = get_api_key(opts)
    model = get_model(opts)

    if is_nil(api_key) or api_key == "" do
      {:error, :api_key_not_set}
    else
      body = Jason.encode!(%{model: model, input: text})

      headers = [
        {"content-type", "application/json"},
        {"authorization", "Bearer #{api_key}"}
      ]

      case Req.post(@api_url, body: body, headers: headers) do
        {:ok, %{status: 200, body: %{"data" => [%{"embedding" => embedding} | _]}}} ->
          {:ok, embedding}

        {:ok, %{status: status, body: body}} ->
          {:error, {:openai_error, status, body}}

        {:error, reason} ->
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
end
