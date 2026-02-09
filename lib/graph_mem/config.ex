defmodule GraphMem.Config do
  @moduledoc """
  Configuration management for GraphMem.

  Provides centralized access to configuration values with validation
  and sensible defaults.

  ## Configuration Options

      config :graph_mem,
        # Storage backend (Postgres default, ETS optional)
        backend: GraphMem.Backends.Postgres,
        repo: MyApp.Repo,

        # Embedding configuration
        embedding_adapter: GraphMem.EmbeddingAdapters.Ollama,
        embedding_model: "nomic-embed-text",
        embedding_dimensions: 768,
        ollama_endpoint: "http://localhost:11434",

        # OpenAI (if using OpenAI adapter)
        openai_api_key: System.get_env("OPENAI_API_KEY"),

        # Auto-linking configuration
        auto_link: true,
        link_threshold: 0.75,
        link_max_candidates: 20,
        link_max_links: 5,

        # Async task supervision
        task_supervisor: GraphMem.TaskSupervisor,

        # HTTP client options
        http_timeout: 30_000,
        http_retry: 2,

        # Qdrant configuration (optional)
        qdrant_url: "http://localhost:6333",
        qdrant_api_key: System.get_env("QDRANT_API_KEY"),
        qdrant_collection: "graph_mem",

        # Reflection adapter (optional)
        reflection_adapter: nil
  """

  require Logger

  @doc """
  Returns the configured storage backend module.

  Uses the following priority:
  1. Explicitly configured `:backend`
  2. Postgres if Ecto and Postgres deps are available (default)
  3. ETS as fallback when Postgres deps are not available
  """
  @spec backend() :: module()
  def backend do
    configured = Application.get_env(:graph_mem, :backend)

    cond do
      configured != nil ->
        configured

      postgres_available?() ->
        GraphMem.Backends.Postgres

      true ->
        Logger.warning("""
        GraphMem: Postgres backend not available.
        Ensure you have ecto_sql, postgrex, and pgvector in your dependencies.
        Falling back to ETS backend (in-memory, non-persistent).
        """)

        GraphMem.Backends.ETS
    end
  end

  @doc """
  Returns the configured Ecto repo module.
  """
  @spec repo() :: module() | nil
  def repo do
    Application.get_env(:graph_mem, :repo)
  end

  @doc """
  Returns the configured embedding adapter module.

  Returns `nil` if explicitly set to `nil` (useful for testing).
  Defaults to `GraphMem.EmbeddingAdapters.Ollama`.
  """
  @spec embedding_adapter() :: module() | nil
  def embedding_adapter do
    case Application.fetch_env(:graph_mem, :embedding_adapter) do
      {:ok, nil} -> nil
      {:ok, adapter} -> adapter
      :error -> GraphMem.EmbeddingAdapters.Ollama
    end
  end

  @doc """
  Returns the configured embedding model name.
  """
  @spec embedding_model() :: String.t()
  def embedding_model do
    Application.get_env(:graph_mem, :embedding_model, "nomic-embed-text")
  end

  @doc """
  Returns the embedding dimensions for the configured model.
  """
  @spec embedding_dimensions() :: pos_integer()
  def embedding_dimensions do
    Application.get_env(:graph_mem, :embedding_dimensions, 768)
  end

  @doc """
  Returns the Ollama API endpoint.
  """
  @spec ollama_endpoint() :: String.t()
  def ollama_endpoint do
    Application.get_env(:graph_mem, :ollama_endpoint, "http://localhost:11434")
  end

  @doc """
  Returns the OpenAI API key.
  """
  @spec openai_api_key() :: String.t() | nil
  def openai_api_key do
    Application.get_env(:graph_mem, :openai_api_key) ||
      System.get_env("OPENAI_API_KEY")
  end

  @doc """
  Returns whether auto-linking is enabled.
  """
  @spec auto_link?() :: boolean()
  def auto_link? do
    Application.get_env(:graph_mem, :auto_link, true)
  end

  @doc """
  Returns the similarity threshold for auto-linking.
  """
  @spec link_threshold() :: float()
  def link_threshold do
    threshold = Application.get_env(:graph_mem, :link_threshold, 0.75)
    validate_threshold!(threshold, :link_threshold)
    threshold
  end

  @doc """
  Returns the maximum candidate count for auto-linking.
  """
  @spec link_max_candidates() :: pos_integer()
  def link_max_candidates do
    max_candidates = Application.get_env(:graph_mem, :link_max_candidates, 20)
    validate_positive_integer!(max_candidates, :link_max_candidates)
    max_candidates
  end

  @doc """
  Returns the maximum number of links to create for auto-linking.
  """
  @spec link_max_links() :: pos_integer()
  def link_max_links do
    max_links = Application.get_env(:graph_mem, :link_max_links, 5)
    validate_positive_integer!(max_links, :link_max_links)
    max_links
  end

  @doc """
  Returns the Task.Supervisor name for background tasks.
  """
  @spec task_supervisor() :: module()
  def task_supervisor do
    Application.get_env(:graph_mem, :task_supervisor, GraphMem.TaskSupervisor)
  end

  @doc """
  Returns the HTTP timeout in milliseconds.
  """
  @spec http_timeout() :: pos_integer()
  def http_timeout do
    Application.get_env(:graph_mem, :http_timeout, 30_000)
  end

  @doc """
  Returns the HTTP retry count.
  """
  @spec http_retry() :: non_neg_integer()
  def http_retry do
    Application.get_env(:graph_mem, :http_retry, 2)
  end

  @doc """
  Returns the configured reflection adapter module.
  """
  @spec reflection_adapter() :: module() | nil
  def reflection_adapter do
    Application.get_env(:graph_mem, :reflection_adapter)
  end

  @doc """
  Returns the configured Qdrant base URL.
  """
  @spec qdrant_url() :: String.t() | nil
  def qdrant_url do
    Application.get_env(:graph_mem, :qdrant_url)
  end

  @doc """
  Returns the configured Qdrant API key.
  """
  @spec qdrant_api_key() :: String.t() | nil
  def qdrant_api_key do
    Application.get_env(:graph_mem, :qdrant_api_key) ||
      System.get_env("QDRANT_API_KEY")
  end

  @doc """
  Returns the configured Qdrant collection name.
  """
  @spec qdrant_collection() :: String.t()
  def qdrant_collection do
    Application.get_env(:graph_mem, :qdrant_collection, "graph_mem")
  end

  @doc """
  Validates the configuration and returns any issues.
  """
  @spec validate() :: :ok | {:error, [String.t()]}
  def validate do
    issues = []

    issues =
      if backend() == GraphMem.Backends.Postgres and repo() == nil do
        ["Postgres backend requires :repo to be configured" | issues]
      else
        issues
      end

    issues =
      if backend() == GraphMem.Backends.Qdrant and is_nil(qdrant_url()) do
        ["Qdrant backend requires :qdrant_url to be configured" | issues]
      else
        issues
      end

    issues =
      case Application.get_env(:graph_mem, :link_threshold) do
        nil -> issues
        t when is_number(t) and t >= 0.0 and t <= 1.0 -> issues
        t -> ["link_threshold must be between 0.0 and 1.0, got: #{inspect(t)}" | issues]
      end

    issues =
      case Application.get_env(:graph_mem, :link_max_candidates) do
        nil ->
          issues

        value when is_integer(value) and value > 0 ->
          issues

        value ->
          ["link_max_candidates must be a positive integer, got: #{inspect(value)}" | issues]
      end

    issues =
      case Application.get_env(:graph_mem, :link_max_links) do
        nil -> issues
        value when is_integer(value) and value > 0 -> issues
        value -> ["link_max_links must be a positive integer, got: #{inspect(value)}" | issues]
      end

    if Enum.empty?(issues) do
      :ok
    else
      {:error, Enum.reverse(issues)}
    end
  end

  defp postgres_available? do
    Code.ensure_loaded?(Ecto) and
      Code.ensure_loaded?(GraphMem.Backends.Postgres)
  end

  defp validate_threshold!(value, _name)
       when is_number(value) and value >= 0.0 and value <= 1.0 do
    :ok
  end

  defp validate_threshold!(value, name) do
    raise ArgumentError, "#{name} must be between 0.0 and 1.0, got: #{inspect(value)}"
  end

  defp validate_positive_integer!(value, _name) when is_integer(value) and value > 0 do
    :ok
  end

  defp validate_positive_integer!(value, name) do
    raise ArgumentError, "#{name} must be a positive integer, got: #{inspect(value)}"
  end
end
