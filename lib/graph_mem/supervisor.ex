defmodule GraphMem.Supervisor do
  @moduledoc """
  Main supervisor for GraphMem.

  Starts the configured backend and task supervisor for async operations.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    backend = Keyword.get(opts, :backend) || get_backend()
    backend_opts = Keyword.get(opts, :backend_opts, [])

    children = [
      {Task.Supervisor, name: GraphMem.TaskSupervisor},
      {backend, backend_opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp get_backend do
    Application.get_env(:graph_mem, :backend, GraphMem.Backends.ETS)
  end
end
