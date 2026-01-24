defmodule GraphMem.ReflectionAdapter do
  @moduledoc """
  Behaviour for reflection adapters.

  Reflection adapters synthesize higher-level insights from a collection
  of memories, typically using an LLM. This is optional - if no adapter
  is configured, GraphMem falls back to a simple text summary.

  ## Implementing a Custom Adapter

      defmodule MyApp.LLMReflection do
        @behaviour GraphMem.ReflectionAdapter

        @impl true
        def reflect(memories, topic) do
          # Call your LLM to synthesize memories
          {:ok, "Synthesized insight..."}
        end
      end

  Configure GraphMem to use your adapter:

      config :graph_mem,
        reflection_adapter: MyApp.LLMReflection
  """

  alias GraphMem.Memory

  @doc """
  Generates a reflection from a list of memories.

  ## Parameters

  - `memories` - List of Memory structs to synthesize
  - `topic` - Optional focus topic (may be nil)

  ## Returns

  - `{:ok, reflection_text}` - The synthesized reflection
  - `{:error, term}` - Error description
  """
  @callback reflect(memories :: [Memory.t()], topic :: String.t() | nil) ::
              {:ok, String.t()} | {:error, term()}
end
