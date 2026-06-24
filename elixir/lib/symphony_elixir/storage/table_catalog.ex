defmodule SymphonyElixir.Storage.TableCatalog do
  @moduledoc """
  Platform-level inventory of storage tables.

  The catalog is for global visibility and conflict checks. It intentionally
  records table ownership and purpose only; column identifiers and projection
  rules remain in subsystem storage contracts.

  Boundary ownership:

  - `Storage.TableCatalog` owns the stable table-inventory facade.
  - `Storage.TableCatalog.Source` owns the source protocol.
  - `Storage.TableCatalog.Entry` owns the normalized table-level record.
  - `AssemblyCatalog.StorageContracts` owns application assembly for bundled
    storage contract modules.

  This module must not compile-depend on concrete domain modules, scan source
  files for runtime registration, or accept subsystem schema details such as
  column lists, indexes, SQL fragments, projections, or upsert rules.
  """

  alias SymphonyElixir.Storage.ErrorCodes
  alias SymphonyElixir.Storage.TableCatalog.Entry
  alias SymphonyElixir.Storage.TableCatalog.Source

  @app :symphony_elixir
  @config_key :storage_table_catalog
  @application_config_keys [:sources]
  @function_only_config_keys [:entry_modules, :extra_entry_modules, :extra_sources]

  @type backend :: :sqlite
  @type entry :: Entry.t()

  @type duplicate_table :: %{
          required(:backend) => backend(),
          required(:table_name) => String.t(),
          required(:owners) => [atom()]
        }

  @type opts :: [
          sources: [module() | {module(), keyword()}],
          extra_sources: [module() | {module(), keyword()}],
          entry_modules: [module()],
          extra_entry_modules: [module()]
        ]

  @spec entries(opts()) :: [entry()]
  def entries(opts \\ []) do
    opts
    |> entry_modules()
    |> Enum.map(&entry_from_module!/1)
    |> Enum.sort_by(fn entry -> {entry.backend, entry.table_name} end)
  end

  @spec sqlite_entries(opts()) :: [entry()]
  def sqlite_entries(opts \\ []) do
    opts
    |> entries()
    |> Enum.filter(&(&1.backend == :sqlite))
  end

  @spec table_names(opts()) :: [String.t()]
  def table_names(opts \\ []) do
    opts
    |> entries()
    |> Enum.map(& &1.table_name)
  end

  @spec fetch(backend(), atom() | String.t(), opts()) :: {:ok, entry()} | :error
  def fetch(backend, table, opts \\ []) do
    table_name = table_name(table)

    opts
    |> entries()
    |> Enum.find(&(&1.backend == backend and &1.table_name == table_name))
    |> case do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  @spec duplicate_tables(opts()) :: [duplicate_table()]
  def duplicate_tables(opts \\ []) do
    opts
    |> entries()
    |> Enum.group_by(fn entry -> {entry.backend, entry.table_name} end)
    |> Enum.flat_map(fn
      {_table_ref, [_entry]} ->
        []

      {{backend, table_name}, entries} ->
        [
          %{
            backend: backend,
            table_name: table_name,
            owners: Enum.map(entries, & &1.owner)
          }
        ]
    end)
  end

  @spec validate(opts()) :: :ok | {:error, map()}
  def validate(opts \\ []) do
    case duplicate_tables(opts) do
      [] ->
        :ok

      duplicates ->
        {:error,
         %{
           code: ErrorCodes.catalog_invalid(),
           message: "Storage catalog has duplicate table registrations.",
           duplicates: duplicates
         }}
    end
  end

  @spec validate!(opts()) :: :ok
  def validate!(opts \\ []) do
    case validate(opts) do
      :ok ->
        :ok

      {:error, %{duplicates: duplicates}} ->
        raise ArgumentError,
              "duplicate storage catalog table registrations: #{format_duplicates(duplicates)}"
    end
  end

  defp entry_modules(opts) do
    base_modules = base_entry_modules(opts)
    source_modules = source_entry_modules(opts)
    extra_modules = Keyword.get(opts, :extra_entry_modules, [])

    base_modules
    |> Kernel.++(source_modules)
    |> Kernel.++(extra_modules)
    |> Enum.uniq()
  end

  defp base_entry_modules(opts) do
    if Keyword.has_key?(opts, :entry_modules) do
      opts |> Keyword.get(:entry_modules, []) |> List.wrap()
    else
      []
    end
  end

  defp source_entry_modules(opts) do
    opts
    |> source_refs()
    |> Enum.flat_map(&entry_modules_from_source!/1)
  end

  defp source_refs(opts) do
    base_sources =
      cond do
        Keyword.has_key?(opts, :sources) ->
          opts |> Keyword.get(:sources, []) |> List.wrap()

        Keyword.has_key?(opts, :entry_modules) ->
          []

        true ->
          configured_sources()
      end

    extra_sources = opts |> Keyword.get(:extra_sources, []) |> List.wrap()

    base_sources ++ extra_sources
  end

  defp configured_sources do
    config = configured_table_catalog!()

    config
    |> Keyword.get(:sources, [])
    |> List.wrap()
  end

  defp configured_table_catalog! do
    @app
    |> Application.get_env(@config_key, [])
    |> validate_application_config!()
  end

  defp validate_application_config!(config) when is_list(config) do
    unless Keyword.keyword?(config) do
      raise ArgumentError,
            "storage table catalog application configuration must be a keyword list, got #{inspect(config)}"
    end

    invalid_keys =
      config
      |> Keyword.keys()
      |> Enum.reject(&(&1 in @application_config_keys))

    unless invalid_keys == [] do
      function_only_keys = Enum.filter(invalid_keys, &(&1 in @function_only_config_keys))

      raise ArgumentError,
            application_config_error_message(invalid_keys, function_only_keys)
    end

    config
  end

  defp validate_application_config!(config) do
    raise ArgumentError,
          "storage table catalog application configuration must be a keyword list, got #{inspect(config)}"
  end

  defp application_config_error_message(invalid_keys, []),
    do: "storage table catalog application configuration contains unsupported key(s): #{inspect(invalid_keys)}"

  defp application_config_error_message(invalid_keys, function_only_keys) do
    "storage table catalog application configuration must use sources only; " <>
      "#{inspect(invalid_keys)} is not supported and #{inspect(function_only_keys)} is only supported in function opts for tests or explicit assembly"
  end

  defp entry_modules_from_source!({module, opts}) when is_atom(module) and is_list(opts) do
    source_module!(module)
    modules = module.entry_modules(opts)

    unless is_list(modules) do
      raise ArgumentError,
            "storage catalog source #{inspect(module)} must return a list of entry modules"
    end

    modules
  end

  defp entry_modules_from_source!(module) when is_atom(module),
    do: entry_modules_from_source!({module, []})

  defp entry_modules_from_source!(source) do
    raise ArgumentError,
          "storage catalog source must be a module or {module, opts}, got #{inspect(source)}"
  end

  defp source_module!(module) when is_atom(module) do
    Code.ensure_loaded?(module) ||
      raise ArgumentError, "storage catalog source #{inspect(module)} could not be loaded"

    unless function_exported?(module, :entry_modules, 1) do
      raise ArgumentError, "storage catalog source #{inspect(module)} must export entry_modules/1"
    end

    unless implements_behaviour?(module, Source) do
      raise ArgumentError,
            "storage catalog source #{inspect(module)} must implement #{inspect(Source)}"
    end

    module
  end

  defp entry_from_module!(module) when is_atom(module) do
    Code.ensure_loaded?(module) ||
      raise ArgumentError, "storage catalog module #{inspect(module)} could not be loaded"

    unless function_exported?(module, :catalog_entry, 0) do
      raise ArgumentError, "storage catalog module #{inspect(module)} must export catalog_entry/0"
    end

    module.catalog_entry()
    |> Entry.new!()
  end

  defp entry_from_module!(module) do
    raise ArgumentError, "storage catalog entry module must be an atom, got #{inspect(module)}"
  end

  defp format_duplicates(duplicates) do
    Enum.map_join(duplicates, "; ", fn duplicate ->
      "#{duplicate.backend}:#{duplicate.table_name} owners=#{inspect(duplicate.owners)}"
    end)
  end

  defp table_name(table) when is_atom(table), do: Atom.to_string(table)
  defp table_name(table) when is_binary(table), do: table

  defp implements_behaviour?(module, behaviour) do
    module
    |> module_behaviours()
    |> Enum.member?(behaviour)
  end

  defp module_behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.take([:behaviour, :behavior])
    |> Keyword.values()
    |> List.flatten()
  end
end
