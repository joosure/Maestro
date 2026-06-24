defmodule SymphonyElixir.Storage.ConfigTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Storage.Config

  @app :symphony_elixir
  @config_key :storage

  setup do
    original_config = Application.get_env(@app, @config_key)

    on_exit(fn ->
      restore_config(original_config)
    end)

    :ok
  end

  test "normalizes supported platform backend values" do
    assert Config.backends() == [:memory, :sqlite]
    assert Config.external_backend_values() == Enum.map(Config.backends(), &Atom.to_string/1)

    assert Config.backend(platform_storage_backend: :memory) == :memory
    assert Config.backend(platform_storage_backend: "memory") == :memory
    assert Config.backend(platform_storage_backend: :sqlite) == :sqlite
    assert Config.backend(platform_storage_backend: "sqlite") == :sqlite
  end

  test "normalizes application config values" do
    Application.put_env(@app, @config_key, backend: "sqlite")

    assert Config.backend() == :sqlite
    assert Config.sqlite?()
    assert Config.durable?()
  end

  test "treats memory backend as non-durable infrastructure" do
    Application.put_env(@app, @config_key, backend: :memory)

    assert Config.backend() == :memory
    refute Config.sqlite?()
    refute Config.durable?()
  end

  test "fails closed for unsupported platform backend values" do
    Application.put_env(@app, @config_key, backend: "unknown")

    assert_raise ArgumentError, ~r/unsupported platform storage backend/, fn ->
      Config.backend()
    end
  end

  defp restore_config(nil), do: Application.delete_env(@app, @config_key)
  defp restore_config(value), do: Application.put_env(@app, @config_key, value)
end
