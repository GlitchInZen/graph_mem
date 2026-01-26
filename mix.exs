defmodule GraphMem.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/noemaex/graph_mem"

  def project do
    [
      app: :graph_mem,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_add_apps: [:ecto, :ecto_sql, :postgrex, :pgvector],
        flags: [:error_handling, :underspecs]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {GraphMem.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},

      # Web API
      {:plug_cowboy, "~> 2.7"},
      {:plug, "~> 1.16"},
      {:cors_plug, "~> 3.0"},

      # Background job processing
      {:oban, "~> 2.18"},

      # Optional: Postgres backend (recommended for production)
      {:ecto_sql, "~> 3.10", optional: true},
      {:postgrex, "~> 0.17", optional: true},
      {:pgvector, "~> 0.3", optional: true},

      # Dev/Test
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    Graph-based long-term memory for AI agents. Provides persistent memory with
    automatic relationship discovery, semantic search via vector embeddings, and
    graph-based retrieval. Features pluggable storage backends (ETS, PostgreSQL)
    and embedding adapters (Ollama, OpenAI).
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["NoemaEx Team"],
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "GraphMem",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "Core API": [
          GraphMem,
          GraphMem.Memory,
          GraphMem.Edge,
          GraphMem.AccessContext
        ],
        "Storage Backends": [
          GraphMem.Backend,
          GraphMem.Backends.ETS,
          GraphMem.Backends.Postgres
        ],
        "Embedding Adapters": [
          GraphMem.EmbeddingAdapter,
          GraphMem.EmbeddingAdapters.Ollama,
          GraphMem.EmbeddingAdapters.OpenAI
        ],
        Configuration: [
          GraphMem.Config
        ],
        Services: [
          GraphMem.Services.Storage,
          GraphMem.Services.Retrieval,
          GraphMem.Services.Graph,
          GraphMem.Services.Linker,
          GraphMem.Services.Reduction
        ],
        "Async Embedding": [
          GraphMem.Embedding.Batcher,
          GraphMem.Embedding.Indexer,
          GraphMem.Workers.EmbeddingIndexJob
        ]
      ]
    ]
  end

  defp aliases do
    [
      test: ["test"],
      lint: ["format --check-formatted", "credo --strict"]
    ]
  end
end
