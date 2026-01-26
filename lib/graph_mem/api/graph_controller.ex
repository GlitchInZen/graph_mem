defmodule GraphMem.API.GraphController do
  @moduledoc """
  Controller for graph-related API endpoints.
  """

  import GraphMem.API.JSON

  def create_edge(conn, %{"agent_id" => agent_id} = params) do
    from_id = params["from_id"]
    to_id = params["to_id"]

    cond do
      is_nil(from_id) ->
        send_error(conn, 400, "from_id is required")

      is_nil(to_id) ->
        send_error(conn, 400, "to_id is required")

      true ->
        type = params["type"] || "relates_to"
        opts = build_edge_opts(params)

        case GraphMem.link(agent_id, from_id, to_id, type, opts) do
          {:ok, edge} ->
            send_json(conn, 201, %{data: serialize(edge)})

          {:error, :not_found} ->
            send_error(conn, 404, "one or both memories not found")

          {:error, :access_denied} ->
            send_error(conn, 403, "access denied")

          {:error, reason} ->
            send_error(conn, 422, inspect(reason))
        end
    end
  end

  def neighbors(conn, %{"agent_id" => agent_id, "id" => memory_id} = params) do
    direction = parse_direction(params["direction"])
    opts = build_neighbors_opts(params)

    case GraphMem.neighbors(agent_id, memory_id, direction, opts) do
      {:ok, results} ->
        send_json(conn, 200, %{data: serialize(results)})

      {:error, :not_found} ->
        send_error(conn, 404, "memory not found")

      {:error, :access_denied} ->
        send_error(conn, 403, "access denied")

      {:error, reason} ->
        send_error(conn, 500, inspect(reason))
    end
  end

  def expand(conn, %{"agent_id" => agent_id} = params) do
    seed_ids = params["seed_ids"] || []

    if seed_ids == [] do
      send_error(conn, 400, "seed_ids is required")
    else
      opts = build_expand_opts(params)

      case GraphMem.expand(agent_id, seed_ids, opts) do
        {:ok, %{memories: memories, edges: edges}} ->
          send_json(conn, 200, %{
            data: %{
              memories: serialize(memories),
              edges: serialize(edges)
            }
          })

        {:error, reason} ->
          send_error(conn, 500, inspect(reason))
      end
    end
  end

  # Option builders

  defp build_edge_opts(params) do
    build_context_opts(params)
    |> maybe_put(:weight, params["weight"], &parse_float/1)
    |> maybe_put(:confidence, params["confidence"], &parse_float/1)
    |> maybe_put(:metadata, params["metadata"])
  end

  defp build_neighbors_opts(params) do
    build_context_opts(params)
    |> maybe_put(:type, params["type"])
    |> maybe_put(:min_weight, params["min_weight"], &parse_float/1)
    |> maybe_put(:limit, params["limit"], &parse_int/1)
  end

  defp build_expand_opts(params) do
    build_context_opts(params)
    |> maybe_put(:depth, params["depth"], &parse_int/1)
    |> maybe_put(:min_weight, params["min_weight"], &parse_float/1)
    |> maybe_put(:min_confidence, params["min_confidence"], &parse_float/1)
    |> maybe_put(:limit, params["limit"], &parse_int/1)
  end

  defp build_context_opts(params) do
    []
    |> maybe_put(:tenant_id, params["tenant_id"])
    |> maybe_put(:allow_shared, params["allow_shared"], &parse_bool/1)
    |> maybe_put(:allow_global, params["allow_global"], &parse_bool/1)
  end

  defp parse_direction(nil), do: :outgoing
  defp parse_direction("outgoing"), do: :outgoing
  defp parse_direction("incoming"), do: :incoming
  defp parse_direction("both"), do: :both
  defp parse_direction(_), do: :outgoing

  defp maybe_put(opts, _key, nil, _transform), do: opts
  defp maybe_put(opts, key, value, transform), do: Keyword.put(opts, key, transform.(value))

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(val) when is_binary(val), do: String.to_integer(val)

  defp parse_float(val) when is_float(val), do: val
  defp parse_float(val) when is_integer(val), do: val / 1
  defp parse_float(val) when is_binary(val), do: String.to_float(val)

  defp parse_bool(val) when is_boolean(val), do: val
  defp parse_bool("true"), do: true
  defp parse_bool("false"), do: false
  defp parse_bool("1"), do: true
  defp parse_bool("0"), do: false
end
