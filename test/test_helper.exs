ExUnit.start()

# Disable embedding adapter for tests to avoid network calls
Application.put_env(:graph_mem, :embedding_adapter, nil)

# Use ETS backend for tests (no Postgres repo available)
Application.put_env(:graph_mem, :backend, GraphMem.Backends.ETS)
