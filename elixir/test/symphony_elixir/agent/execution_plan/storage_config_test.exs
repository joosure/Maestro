defmodule SymphonyElixir.Agent.ExecutionPlan.Storage.ConfigTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Agent.ExecutionPlan.Storage.Config
  alias SymphonyElixir.Agent.ExecutionPlan.Storage.MemoryBackend
  alias SymphonyElixir.Agent.ExecutionPlan.Storage.SQLiteBackend

  @app :symphony_elixir
  @config_key :agent_execution_plan
  @platform_config_key :storage

  setup do
    original_config = Application.get_env(@app, @config_key)
    original_platform_config = Application.get_env(@app, @platform_config_key)

    on_exit(fn ->
      restore_config(original_config)
      restore_platform_config(original_platform_config)
    end)

    :ok
  end

  test "normalizes explicit backend module overrides" do
    assert Config.backend(backend: MemoryBackend) == MemoryBackend
    assert Config.backend(backend: SQLiteBackend) == SQLiteBackend
  end

  test "fails closed for unsupported explicit backend values" do
    assert_raise ArgumentError, ~r/unsupported Agent execution-plan storage backend/, fn ->
      Config.backend(backend: :unknown)
    end

    assert_raise ArgumentError, ~r/unsupported Agent execution-plan storage backend/, fn ->
      Config.backend(backend: "unknown")
    end
  end

  test "normalizes domain storage mode and platform durable backend" do
    Application.put_env(@app, @platform_config_key, backend: :sqlite)
    Application.put_env(@app, @config_key, storage: "durable")

    assert Config.storage_mode() == :durable
    assert Config.backend() == SQLiteBackend
    assert Config.durable?()
  end

  test "uses memory backend for memory storage mode" do
    Application.put_env(@app, @platform_config_key, backend: :sqlite)
    Application.put_env(@app, @config_key, storage: :memory)

    assert Config.storage_mode() == :memory
    assert Config.backend() == MemoryBackend
    refute Config.durable?()
  end

  test "fails closed when durable mode has no durable platform backend" do
    Application.put_env(@app, @platform_config_key, backend: :memory)
    Application.put_env(@app, @config_key, storage: :durable)

    assert_raise ArgumentError, ~r/unsupported Agent execution-plan storage backend/, fn ->
      Config.backend(backend: :sqlite)
    end

    assert_raise ArgumentError, ~r/requires a durable platform storage backend/, fn ->
      Config.backend()
    end
  end

  defp restore_config(nil), do: Application.delete_env(@app, @config_key)
  defp restore_config(value), do: Application.put_env(@app, @config_key, value)

  defp restore_platform_config(nil), do: Application.delete_env(@app, @platform_config_key)
  defp restore_platform_config(value), do: Application.put_env(@app, @platform_config_key, value)
end
