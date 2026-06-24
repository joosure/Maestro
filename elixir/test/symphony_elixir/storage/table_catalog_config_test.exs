defmodule SymphonyElixir.Storage.TableCatalogConfigTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Storage.TableCatalog

  @app :symphony_elixir
  @config_key :storage_table_catalog

  setup do
    original = Application.get_env(@app, @config_key)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(@app, @config_key)
        value -> Application.put_env(@app, @config_key, value)
      end
    end)
  end

  test "application configuration rejects direct entry modules" do
    Application.put_env(@app, @config_key, entry_modules: [__MODULE__])

    assert_raise ArgumentError, ~r/application configuration must use sources/, fn ->
      TableCatalog.entries()
    end
  end

  test "application configuration rejects direct extra entry modules" do
    Application.put_env(@app, @config_key, extra_entry_modules: [__MODULE__])

    assert_raise ArgumentError, ~r/application configuration must use sources/, fn ->
      TableCatalog.entries()
    end
  end

  test "application configuration rejects extra sources" do
    Application.put_env(@app, @config_key, sources: [], extra_sources: [])

    assert_raise ArgumentError, ~r/extra_sources.*only supported in function opts/, fn ->
      TableCatalog.entries()
    end
  end

  test "application configuration rejects unknown keys" do
    Application.put_env(@app, @config_key, sourcez: [])

    assert_raise ArgumentError, ~r/unsupported key\(s\): \[:sourcez\]/, fn ->
      TableCatalog.entries()
    end
  end

  test "application configuration rejects non-keyword lists" do
    Application.put_env(@app, @config_key, [:not_a_tuple])

    assert_raise ArgumentError, ~r/must be a keyword list/, fn ->
      TableCatalog.entries()
    end
  end

  test "application configuration rejects non-list values" do
    Application.put_env(@app, @config_key, %{sources: []})

    assert_raise ArgumentError, ~r/must be a keyword list/, fn ->
      TableCatalog.entries()
    end
  end
end
