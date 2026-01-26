defmodule GraphMem.API.JSON do
  @moduledoc """
  JSON serialization helpers for API responses.
  """

  alias GraphMem.{Memory, Edge}

  def send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  def send_error(conn, status, message) do
    send_json(conn, status, %{error: message})
  end

  def serialize(%Memory{} = memory) do
    %{
      id: memory.id,
      type: memory.type,
      summary: memory.summary,
      content: memory.content,
      importance: memory.importance,
      confidence: memory.confidence,
      scope: memory.scope,
      agent_id: memory.agent_id,
      tenant_id: memory.tenant_id,
      tags: memory.tags,
      metadata: memory.metadata,
      session_id: memory.session_id,
      access_count: memory.access_count,
      last_accessed_at: serialize_datetime(memory.last_accessed_at),
      inserted_at: serialize_datetime(memory.inserted_at),
      updated_at: serialize_datetime(memory.updated_at)
    }
  end

  def serialize(%Edge{} = edge) do
    %{
      id: edge.id,
      from_id: edge.from_id,
      to_id: edge.to_id,
      type: edge.type,
      weight: edge.weight,
      confidence: edge.confidence,
      scope: edge.scope,
      metadata: edge.metadata,
      inserted_at: serialize_datetime(edge.inserted_at)
    }
  end

  def serialize(%{memory: memory, score: score}) do
    %{memory: serialize(memory), score: score}
  end

  def serialize(%{memory: memory, edge: edge}) do
    %{memory: serialize(memory), edge: serialize(edge)}
  end

  def serialize(list) when is_list(list) do
    Enum.map(list, &serialize/1)
  end

  def serialize(other), do: other

  defp serialize_datetime(nil), do: nil
  defp serialize_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
