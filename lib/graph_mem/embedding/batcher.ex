defmodule GraphMem.Embedding.Batcher do
  @moduledoc """
  Simple batching GenServer for embedding requests.

  - Collects requests for up to `:batch_timeout_ms` (default 50ms) or until
    `:batch_size` (default 32) is reached, then calls the embedding adapter's
    `embed_many/2` API (or falls back to sequential calls).
  - Each caller does a synchronous `GenServer.call/3` and receives a reply when
    the batch completes.

  ## Limitations

  - All requests in a batch use the opts from the first request. Callers should
    ensure uniform opts (same model/endpoint) or partition batching externally.
  """

  use GenServer
  require Logger

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Request an embedding for a single text. Blocks until batch is processed."
  def request(text, opts \\ []) when is_binary(text) do
    GenServer.call(__MODULE__, {:embed, text, opts}, 60_000)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    timeout_ms = Application.get_env(:graph_mem, :batch_timeout_ms, 50)
    batch_size = Application.get_env(:graph_mem, :batch_size, 32)

    {:ok,
     %{
       pending: [],
       timer_ref: nil,
       timeout_ms: timeout_ms,
       batch_size: batch_size
     }}
  end

  @impl true
  def handle_call({:embed, text, opts}, from, state) do
    pending = [{from, text, opts} | state.pending]
    state = maybe_start_timer(%{state | pending: pending})

    if length(pending) >= state.batch_size do
      {:noreply, flush(state)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:flush, ref}, %{timer_ref: ref} = state) do
    {:noreply, flush(state)}
  end

  def handle_info({:flush, _stale_ref}, state) do
    # Stale timer message from a previous batch; ignore
    {:noreply, state}
  end

  # Private functions

  defp maybe_start_timer(%{timer_ref: nil, timeout_ms: t} = state) do
    ref = make_ref()
    Process.send_after(self(), {:flush, ref}, t)
    %{state | timer_ref: ref}
  end

  defp maybe_start_timer(state), do: state

  defp cancel_timer(%{timer_ref: nil} = state), do: state

  defp cancel_timer(%{timer_ref: _ref} = state) do
    # Timer ref approach means we just ignore stale messages; no need to cancel
    # But clear the ref so a new timer can be started for the next batch
    %{state | timer_ref: nil}
  end

  defp flush(%{pending: []} = state) do
    cancel_timer(state)
  end

  defp flush(%{pending: pending} = state) do
    # Reset timer/pending early to accept new requests immediately
    pending = Enum.reverse(pending)
    state = %{state | pending: [], timer_ref: nil}

    {froms, texts, opts_list} =
      Enum.reduce(pending, {[], [], []}, fn {from, text, opts}, {fs, ts, os} ->
        {[from | fs], [text | ts], [opts | os]}
      end)

    # Reverse to maintain order matching texts
    froms = Enum.reverse(froms)
    texts = Enum.reverse(texts)

    # Use opts from first request (documented limitation)
    opts = List.last(opts_list) || []

    result =
      case GraphMem.EmbeddingAdapter.embed_many(texts, opts) do
        {:ok, embeddings} when length(embeddings) == length(texts) ->
          {:ok, embeddings}

        {:ok, embeddings} ->
          {:error, {:length_mismatch, expected: length(texts), got: length(embeddings)}}

        {:error, reason} ->
          {:error, reason}
      end

    case result do
      {:ok, embeddings} ->
        Enum.zip(froms, embeddings)
        |> Enum.each(fn {from, emb} -> GenServer.reply(from, {:ok, emb}) end)

      {:error, reason} ->
        Logger.warning("Embedding batch failed: #{inspect(reason)}")
        Enum.each(froms, fn from -> GenServer.reply(from, {:error, reason}) end)
    end

    state
  end
end
