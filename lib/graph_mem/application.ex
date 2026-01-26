defmodule GraphMem.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = api_children()

    opts = [strategy: :one_for_one, name: GraphMem.ApplicationSupervisor]
    Supervisor.start_link(children, opts)
  end

  defp api_children do
    if Application.get_env(:graph_mem, :api_enabled, false) do
      port = Application.get_env(:graph_mem, :api_port, 4000)

      [
        {Plug.Cowboy, scheme: :http, plug: GraphMem.API.Router, options: [port: port]}
      ]
    else
      []
    end
  end
end
