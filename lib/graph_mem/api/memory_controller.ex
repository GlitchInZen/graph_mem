defmodule GraphMem.API.MemoryController do
  @moduledoc """
  Controller for memory-related API endpoints.
  """

  import GraphMem.API.JSON

  def create(conn, %{"agent_id" => agent_id} = params) do
    text = params["text"] || params["content"]

    if is_nil(text) do
      send_error(conn, 400, "text is required")
    else
      opts = build_remember_opts(params)

      case GraphMem.remember(agent_id, text, opts) do
        {:ok, memory} ->
          send_json(conn, 201, %{data: serialize(memory)})

        {:error, reason} ->
          send_error(conn, 422, inspect(reason))
      end
    end
  end

  def index(conn, %{"agent_id" => agent_id} = params) do
    opts = build_list_opts(params)

    case GraphMem.list_memories(agent_id, opts) do
      {:ok, memories} ->
        send_json(conn, 200, %{data: serialize(memories)})

      {:error, reason} ->
        send_error(conn, 500, inspect(reason))
    end
  end

  def show(conn, %{"agent_id" => agent_id, "id" => id} = params) do
    opts = build_context_opts(params)

    case GraphMem.get_memory(agent_id, id, opts) do
      {:ok, memory} ->
        send_json(conn, 200, %{data: serialize(memory)})

      {:error, :not_found} ->
        send_error(conn, 404, "memory not found")

      {:error, :access_denied} ->
        send_error(conn, 403, "access denied")

      {:error, reason} ->
        send_error(conn, 500, inspect(reason))
    end
  end

  def delete(conn, %{"agent_id" => agent_id, "id" => id} = params) do
    opts = build_context_opts(params)

    case GraphMem.delete_memory(agent_id, id, opts) do
      :ok ->
        send_json(conn, 200, %{data: %{deleted: true}})

      {:error, :not_found} ->
        send_error(conn, 404, "memory not found")

      {:error, :access_denied} ->
        send_error(conn, 403, "access denied")

      {:error, reason} ->
        send_error(conn, 500, inspect(reason))
    end
  end

  def recall(conn, %{"agent_id" => agent_id} = params) do
    query = params["q"] || params["query"]

    if is_nil(query) do
      send_error(conn, 400, "query parameter 'q' is required")
    else
      opts = build_recall_opts(params)

      case GraphMem.recall(agent_id, query, opts) do
        {:ok, results} ->
          send_json(conn, 200, %{data: serialize(results)})

        {:error, reason} ->
          send_error(conn, 500, inspect(reason))
      end
    end
  end

  def recall_context(conn, %{"agent_id" => agent_id} = params) do
    query = params["q"] || params["query"]

    if is_nil(query) do
      send_error(conn, 400, "query parameter 'q' is required")
    else
      opts = build_recall_context_opts(params)

      case GraphMem.recall_context(agent_id, query, opts) do
        {:ok, context} ->
          send_json(conn, 200, %{data: %{context: context}})

        {:error, reason} ->
          send_error(conn, 500, inspect(reason))
      end
    end
  end

  def reflect(conn, %{"agent_id" => agent_id} = params) do
    opts = build_reflect_opts(params)

    case GraphMem.reflect(agent_id, opts) do
      {:ok, %GraphMem.Memory{} = memory} ->
        send_json(conn, 201, %{data: serialize(memory)})

      {:ok, text} when is_binary(text) ->
        send_json(conn, 200, %{data: %{reflection: text}})

      {:error, :insufficient_memories} ->
        send_error(conn, 422, "insufficient memories for reflection")

      {:error, reason} ->
        send_error(conn, 500, inspect(reason))
    end
  end

  # Option builders

  defp build_remember_opts(params) do
    []
    |> maybe_put(:type, params["type"], &String.to_atom/1)
    |> maybe_put(:summary, params["summary"])
    |> maybe_put(:importance, params["importance"], &parse_float/1)
    |> maybe_put(:confidence, params["confidence"], &parse_float/1)
    |> maybe_put(:scope, params["scope"], &String.to_atom/1)
    |> maybe_put(:tenant_id, params["tenant_id"])
    |> maybe_put(:tags, params["tags"])
    |> maybe_put(:metadata, params["metadata"])
    |> maybe_put(:session_id, params["session_id"])
    |> maybe_put(:link, params["link"], &parse_bool/1)
  end

  defp build_list_opts(params) do
    build_context_opts(params)
    |> maybe_put(:limit, params["limit"], &parse_int/1)
    |> maybe_put(:offset, params["offset"], &parse_int/1)
    |> maybe_put(:type, params["type"], &String.to_atom/1)
    |> maybe_put(:tags, params["tags"])
  end

  defp build_recall_opts(params) do
    build_context_opts(params)
    |> maybe_put(:limit, params["limit"], &parse_int/1)
    |> maybe_put(:threshold, params["threshold"], &parse_float/1)
    |> maybe_put(:type, params["type"], &String.to_atom/1)
    |> maybe_put(:tags, params["tags"])
    |> maybe_put(:min_confidence, params["min_confidence"], &parse_float/1)
    |> maybe_put(:expand_graph, params["expand_graph"], &parse_bool/1)
    |> maybe_put(:graph_depth, params["graph_depth"], &parse_int/1)
  end

  defp build_recall_context_opts(params) do
    build_recall_opts(params)
    |> maybe_put(:format, params["format"], &String.to_atom/1)
    |> maybe_put(:max_tokens, params["max_tokens"], &parse_int/1)
    |> maybe_put(:include_edges, params["include_edges"], &parse_bool/1)
  end

  defp build_reflect_opts(params) do
    build_context_opts(params)
    |> maybe_put(:topic, params["topic"])
    |> maybe_put(:min_memories, params["min_memories"], &parse_int/1)
    |> maybe_put(:max_memories, params["max_memories"], &parse_int/1)
    |> maybe_put(:store, params["store"], &parse_bool/1)
  end

  defp build_context_opts(params) do
    []
    |> maybe_put(:tenant_id, params["tenant_id"])
    |> maybe_put(:allow_shared, params["allow_shared"], &parse_bool/1)
    |> maybe_put(:allow_global, params["allow_global"], &parse_bool/1)
  end

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
