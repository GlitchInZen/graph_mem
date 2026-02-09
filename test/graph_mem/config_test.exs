defmodule GraphMem.ConfigTest do
  use ExUnit.Case

  alias GraphMem.Config

  setup do
    original_backend = Application.get_env(:graph_mem, :backend)

    on_exit(fn ->
      Application.put_env(:graph_mem, :embedding_adapter, nil)

      if original_backend do
        Application.put_env(:graph_mem, :backend, original_backend)
      else
        Application.delete_env(:graph_mem, :backend)
      end
    end)

    :ok
  end

  describe "backend/0" do
    test "returns Postgres when no backend configured and Postgres available" do
      Application.delete_env(:graph_mem, :backend)
      Application.delete_env(:graph_mem, :repo)

      assert Config.backend() == GraphMem.Backends.Postgres
    end

    test "returns configured backend when explicitly set" do
      Application.put_env(:graph_mem, :backend, GraphMem.Backends.ETS)

      assert Config.backend() == GraphMem.Backends.ETS

      Application.delete_env(:graph_mem, :backend)
    end
  end

  describe "embedding_adapter/0" do
    test "defaults to Ollama" do
      Application.delete_env(:graph_mem, :embedding_adapter)

      assert Config.embedding_adapter() == GraphMem.EmbeddingAdapters.Ollama
    end

    test "returns configured adapter" do
      Application.put_env(:graph_mem, :embedding_adapter, GraphMem.EmbeddingAdapters.OpenAI)

      assert Config.embedding_adapter() == GraphMem.EmbeddingAdapters.OpenAI

      Application.delete_env(:graph_mem, :embedding_adapter)
    end
  end

  describe "embedding_model/0" do
    test "defaults to nomic-embed-text" do
      Application.delete_env(:graph_mem, :embedding_model)

      assert Config.embedding_model() == "nomic-embed-text"
    end
  end

  describe "ollama_endpoint/0" do
    test "defaults to localhost:11434" do
      Application.delete_env(:graph_mem, :ollama_endpoint)

      assert Config.ollama_endpoint() == "http://localhost:11434"
    end
  end

  describe "auto_link?/0" do
    test "defaults to true" do
      Application.delete_env(:graph_mem, :auto_link)

      assert Config.auto_link?() == true
    end
  end

  describe "link_threshold/0" do
    test "defaults to 0.75" do
      Application.delete_env(:graph_mem, :link_threshold)

      assert Config.link_threshold() == 0.75
    end

    test "raises on invalid threshold" do
      Application.put_env(:graph_mem, :link_threshold, 1.5)

      assert_raise ArgumentError, fn ->
        Config.link_threshold()
      end

      Application.delete_env(:graph_mem, :link_threshold)
    end
  end

  describe "http_timeout/0" do
    test "defaults to 30_000" do
      Application.delete_env(:graph_mem, :http_timeout)

      assert Config.http_timeout() == 30_000
    end
  end

  describe "http_retry/0" do
    test "defaults to 2" do
      Application.delete_env(:graph_mem, :http_retry)

      assert Config.http_retry() == 2
    end
  end

  describe "validate/0" do
    test "returns ok for valid config with ETS backend" do
      Application.put_env(:graph_mem, :backend, GraphMem.Backends.ETS)
      Application.delete_env(:graph_mem, :repo)
      Application.delete_env(:graph_mem, :link_threshold)

      assert Config.validate() == :ok
    end

    test "returns error when Postgres backend without repo" do
      Application.put_env(:graph_mem, :backend, GraphMem.Backends.Postgres)
      Application.delete_env(:graph_mem, :repo)

      assert {:error, issues} = Config.validate()
      assert "Postgres backend requires :repo to be configured" in issues
    end

    test "returns error for invalid link_threshold" do
      Application.put_env(:graph_mem, :link_threshold, 2.0)

      assert {:error, issues} = Config.validate()
      assert length(issues) > 0

      Application.delete_env(:graph_mem, :link_threshold)
    end
  end
end
