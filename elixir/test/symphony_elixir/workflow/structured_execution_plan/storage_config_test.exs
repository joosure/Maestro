defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.ConfigTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Storage.Config, as: PlatformStorageConfig
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.Config
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.MemoryBackend
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.SQLiteBackend

  @app :symphony_elixir
  @config_key :workflow_execution_plan_adoption
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
    assert Config.backend(workflow_storage_backend: MemoryBackend) == MemoryBackend
    assert Config.backend(workflow_storage_backend: SQLiteBackend) == SQLiteBackend
  end

  test "normalizes domain storage mode and platform durable backend" do
    Application.put_env(@app, @platform_config_key, backend: :sqlite)
    Application.put_env(@app, @config_key, storage: "durable")

    assert PlatformStorageConfig.backend() == :sqlite
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

  test "fails closed for unsupported storage mode values" do
    Application.put_env(@app, @config_key, storage: "unknown")

    assert_raise ArgumentError, ~r/unsupported Workflow structured execution-plan storage mode/, fn ->
      Config.storage_mode()
    end
  end

  defp restore_config(nil), do: Application.delete_env(@app, @config_key)
  defp restore_config(value), do: Application.put_env(@app, @config_key, value)

  defp restore_platform_config(nil), do: Application.delete_env(@app, @platform_config_key)
  defp restore_platform_config(value), do: Application.put_env(@app, @platform_config_key, value)
end
