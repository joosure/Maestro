defmodule SymphonyElixir.Agent.DynamicTool.Source.Config do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Source
  alias SymphonyElixir.Agent.DynamicTool.Source.Config.SourceSpec
  alias SymphonyElixir.Agent.DynamicTool.SourceCatalog

  @app :symphony_elixir
  @source_key :dynamic_tool_source
  @sources_key :dynamic_tool_sources
  @source_config_keys [:catalogs, :extra_catalogs, :sources, :extra_sources, :source_opts]

  @type source_spec :: SourceSpec.t()

  @spec default_source(module()) :: module()
  def default_source(composite_source) when is_atom(composite_source) do
    case Application.fetch_env(@app, @source_key) do
      {:ok, source} ->
        Source.validate!(source)

      :error ->
        _source_specs = source_specs_from_application!()
        composite_source
    end
  end

  @spec source_from_opts(keyword(), module()) :: module()
  def source_from_opts(opts, composite_source) when is_list(opts) and is_atom(composite_source) do
    cond do
      Keyword.has_key?(opts, @source_key) ->
        opts
        |> Keyword.fetch!(@source_key)
        |> Source.validate!()

      Keyword.has_key?(opts, @sources_key) ->
        _source_specs = source_specs_from_opts!(opts)
        composite_source

      true ->
        default_source(composite_source)
    end
  end

  @spec source_specs!(keyword()) :: [source_spec()]
  def source_specs!(opts) when is_list(opts) do
    if Keyword.has_key?(opts, @sources_key) do
      source_specs_from_opts!(opts)
    else
      source_specs_from_application!()
    end
  end

  def source_specs!(_opts), do: raise(ArgumentError, "dynamic tool source options must be a keyword list")

  defp source_specs_from_opts!(opts) do
    opts
    |> Keyword.fetch!(@sources_key)
    |> normalize_opts_source_specs!(@sources_key)
  end

  defp source_specs_from_application! do
    case Application.fetch_env(@app, @sources_key) do
      {:ok, source_config} -> normalize_application_source_specs!(source_config)
      :error -> []
    end
  end

  defp normalize_application_source_specs!(source_config) when is_list(source_config) do
    if source_config?(source_config) do
      source_config
      |> source_specs_from_config!(@sources_key)
      |> normalize_source_specs!(@sources_key)
    else
      raise ArgumentError,
            "invalid #{@sources_key}: application configuration must use :catalogs or :sources, " <>
              "got #{inspect(source_config)}"
    end
  end

  defp normalize_application_source_specs!(source_config) do
    raise ArgumentError,
          "invalid #{@sources_key}: expected a keyword source configuration, got #{inspect(source_config)}"
  end

  defp normalize_opts_source_specs!(source_config, key) when is_list(source_config) do
    if source_config?(source_config) do
      source_config
      |> source_specs_from_config!(key)
      |> normalize_source_specs!(key)
    else
      normalize_source_specs!(source_config, key)
    end
  end

  defp normalize_opts_source_specs!(source_config, key), do: normalize_source_specs!(source_config, key)

  defp source_specs_from_config!(config, key) when is_list(config) do
    :ok = validate_source_config_keys!(config, key)
    source_opts = Keyword.get(config, :source_opts, [])

    unless Keyword.keyword?(source_opts) do
      raise ArgumentError, "invalid #{inspect(key)} :source_opts: expected a keyword list, got #{inspect(source_opts)}"
    end

    config
    |> Keyword.get(:sources, [])
    |> normalize_raw_source_specs!(key)
    |> Kernel.++(catalog_source_specs!(Keyword.get(config, :catalogs, []), source_opts, key))
    |> Kernel.++(normalize_raw_source_specs!(Keyword.get(config, :extra_sources, []), key))
    |> Kernel.++(catalog_source_specs!(Keyword.get(config, :extra_catalogs, []), source_opts, key))
  end

  defp source_config?(source_config) when is_list(source_config) do
    Keyword.keyword?(source_config) and Enum.any?(@source_config_keys, &Keyword.has_key?(source_config, &1))
  end

  defp validate_source_config_keys!(config, key) do
    unknown_keys =
      config
      |> Keyword.keys()
      |> Enum.reject(&(&1 in @source_config_keys))

    case unknown_keys do
      [] ->
        :ok

      keys ->
        raise ArgumentError, "invalid #{inspect(key)} source configuration key(s): #{inspect(keys)}"
    end
  end

  defp normalize_raw_source_specs!(source_specs, _key) when is_list(source_specs), do: source_specs

  defp normalize_raw_source_specs!(source_specs, key) do
    raise ArgumentError,
          "invalid #{inspect(key)} source list: expected a list of dynamic tool source specs, got #{inspect(source_specs)}"
  end

  defp catalog_source_specs!(catalogs, source_opts, key) do
    catalogs
    |> normalize_catalog_refs!(key)
    |> Enum.flat_map(fn {catalog, catalog_opts} ->
      catalog
      |> catalog_source_specs(Keyword.merge(source_opts, catalog_opts))
      |> normalize_catalog_source_specs!(catalog, key)
    end)
  end

  defp catalog_source_specs(catalog, opts), do: catalog.source_specs(opts)

  defp normalize_catalog_source_specs!(source_specs, _catalog, _key) when is_list(source_specs), do: source_specs

  defp normalize_catalog_source_specs!(source_specs, catalog, key) do
    raise ArgumentError,
          "invalid #{inspect(key)} catalog #{inspect(catalog)}: source_specs/1 must return a list, " <>
            "got #{inspect(source_specs)}"
  end

  defp normalize_catalog_refs!(catalogs, key) when is_list(catalogs) do
    Enum.map(catalogs, &normalize_catalog_ref!(&1, key))
  end

  defp normalize_catalog_refs!(catalogs, key) do
    raise ArgumentError, "invalid #{inspect(key)} catalogs: expected a list, got #{inspect(catalogs)}"
  end

  defp normalize_catalog_ref!({catalog, opts}, key) when is_atom(catalog) and is_list(opts) do
    validate_catalog!(catalog, key)
    {catalog, opts}
  end

  defp normalize_catalog_ref!(catalog, key) when is_atom(catalog) and not is_nil(catalog) do
    validate_catalog!(catalog, key)
    {catalog, []}
  end

  defp normalize_catalog_ref!(catalog, key) do
    raise ArgumentError, "invalid #{inspect(key)} catalog entry: #{inspect(catalog)}"
  end

  defp validate_catalog!(catalog, key) do
    cond do
      not Code.ensure_loaded?(catalog) ->
        raise ArgumentError, "invalid #{inspect(key)} catalog #{inspect(catalog)}: module could not be loaded"

      not function_exported?(catalog, :source_specs, 1) ->
        raise ArgumentError, "invalid #{inspect(key)} catalog #{inspect(catalog)}: must export source_specs/1"

      not catalog_behaviour?(catalog) ->
        raise ArgumentError, "invalid #{inspect(key)} catalog #{inspect(catalog)}: must implement #{inspect(SourceCatalog)}"

      true ->
        :ok
    end
  end

  defp catalog_behaviour?(catalog) do
    attributes = catalog.module_info(:attributes)

    behaviours =
      Keyword.get_values(attributes, :behaviour) ++
        Keyword.get_values(attributes, :behavior)

    SourceCatalog in List.flatten(behaviours)
  end

  defp normalize_source_specs!(source_specs, key) when is_list(source_specs) do
    Enum.map(source_specs, &normalize_source_spec!(&1, key))
  end

  defp normalize_source_specs!(source_specs, key) do
    raise ArgumentError,
          "invalid #{inspect(key)}: expected a list of dynamic tool source specs, got #{inspect(source_specs)}"
  end

  defp normalize_source_spec!(source_spec, key), do: SourceSpec.normalize!(source_spec, key)
end
