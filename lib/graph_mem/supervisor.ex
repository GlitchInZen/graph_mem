defmodule GraphMem.Supervisor do
  @moduledoc """
  Main supervisor for GraphMem.

  Starts the configured backend, Oban for job processing, and supporting services.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    backend = Keyword.get(opts, :backend) || get_backend()
    backend_opts = Keyword.get(opts, :backend_opts, [])

    children =
      [
        {Task.Supervisor, name: GraphMem.TaskSupervisor},
        GraphMem.Embedding.Batcher,
        oban_child_spec(opts),
        {backend, backend_opts}
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp oban_child_spec(opts) do
    oban_opts = Keyword.get(opts, :oban, default_oban_opts())

    if oban_opts == false do
      nil
    else
      {Oban, oban_opts}
    end
  end

  defp default_oban_opts do
    repo = Application.get_env(:graph_mem, :repo)

    cond do
      repo != nil ->
        [
          repo: repo,
          queues: [embeddings: 10]
        ]

      Mix.env() == :test ->
        # Disable Oban in tests; fall back to Task.Supervisor
        false

      true ->
        # No repo configured and not in test - Oban can't run without a repo
        false
    end
  end

  defp get_backend do
    Application.get_env(:graph_mem, :backend, GraphMem.Backends.ETS)
  end
end
