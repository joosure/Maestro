defmodule SymphonyElixir.Capability.Registry do
  @moduledoc """
  Aggregates domain-owned capability source modules.

  The registry is an application-assembly mechanism: each domain owns and
  exposes its own capability strings, while Workflow, Config, Observability,
  and other platform contexts consume aggregated sets.
  """

  @type capability :: String.t()

  @spec sources(keyword()) :: [module()]
  def sources(opts \\ []) when is_list(opts) do
    config = Application.get_env(:symphony_elixir, :capability_sources, [])

    {sources, catalogs} = configured_sources_and_catalogs(config, opts)

    sources
    |> Kernel.++(catalog_sources(catalogs))
    |> Kernel.++(Keyword.get(opts, :extra_sources, []))
    |> Kernel.++(Keyword.get(config, :extra_sources, []))
    |> Kernel.++(catalog_sources(Keyword.get(opts, :extra_catalogs, [])))
    |> Kernel.++(catalog_sources(Keyword.get(config, :extra_catalogs, [])))
    |> normalize_sources!()
    |> Enum.uniq()
  end

  @spec capabilities(keyword()) :: [capability()]
  def capabilities(opts \\ []), do: collect(:capabilities, opts)

  @spec typed_tool_capabilities(keyword()) :: [capability()]
  def typed_tool_capabilities(opts \\ []), do: collect(:typed_tool_capabilities, opts)

  @spec merge_gate_capabilities(keyword()) :: [capability()]
  def merge_gate_capabilities(opts \\ []), do: collect(:merge_gate_capabilities, opts)

  @spec diagnostic_capabilities(keyword()) :: [capability()]
  def diagnostic_capabilities(opts \\ []), do: collect(:diagnostic_capabilities, opts)

  @spec known_provider_unavailable_capabilities(keyword()) :: [capability()]
  def known_provider_unavailable_capabilities(opts \\ []),
    do: collect(:known_provider_unavailable_capabilities, opts)

  @spec typed_tool_capability?(term(), keyword()) :: boolean()
  def typed_tool_capability?(capability, opts \\ [])

  def typed_tool_capability?(capability, opts) when is_binary(capability) and is_list(opts),
    do: MapSet.member?(MapSet.new(typed_tool_capabilities(opts)), capability)

  def typed_tool_capability?(_capability, _opts), do: false

  @spec merge_gate_capability?(term(), keyword()) :: boolean()
  def merge_gate_capability?(capability, opts \\ [])

  def merge_gate_capability?(capability, opts) when is_binary(capability) and is_list(opts),
    do: MapSet.member?(MapSet.new(merge_gate_capabilities(opts)), capability)

  def merge_gate_capability?(_capability, _opts), do: false

  @spec diagnostic_capability?(term(), keyword()) :: boolean()
  def diagnostic_capability?(capability, opts \\ [])

  def diagnostic_capability?(capability, opts) when is_binary(capability) and is_list(opts),
    do: MapSet.member?(MapSet.new(diagnostic_capabilities(opts)), capability)

  def diagnostic_capability?(_capability, _opts), do: false

  @spec known_provider_unavailable_capability?(term(), keyword()) :: boolean()
  def known_provider_unavailable_capability?(capability, opts \\ [])

  def known_provider_unavailable_capability?(capability, opts) when is_binary(capability) and is_list(opts),
    do: MapSet.member?(MapSet.new(known_provider_unavailable_capabilities(opts)), capability)

  def known_provider_unavailable_capability?(_capability, _opts), do: false

  defp collect(callback, opts) when is_atom(callback) and is_list(opts) do
    opts
    |> sources()
    |> Enum.flat_map(&source_capabilities(&1, callback))
    |> Enum.uniq()
  end

  defp configured_sources_and_catalogs(config, opts) do
    cond do
      Keyword.has_key?(opts, :sources) ->
        {Keyword.fetch!(opts, :sources), Keyword.get(opts, :catalogs, [])}

      Keyword.has_key?(opts, :catalogs) ->
        {Keyword.get(opts, :sources, []), Keyword.fetch!(opts, :catalogs)}

      true ->
        {Keyword.get(config, :sources, []), Keyword.get(config, :catalogs, [])}
    end
  end

  defp source_capabilities(source, callback) do
    if function_exported?(source, callback, 0) do
      source
      |> apply(callback, [])
      |> normalize_capabilities!(source, callback)
    else
      []
    end
  end

  defp catalog_sources(catalogs) do
    catalogs
    |> normalize_catalogs!()
    |> Enum.flat_map(fn catalog ->
      catalog
      |> catalog_source_modules()
      |> normalize_catalog_source_modules!(catalog)
    end)
  end

  defp catalog_source_modules(catalog), do: catalog.source_modules()

  defp normalize_catalog_source_modules!(source_modules, _catalog) when is_list(source_modules),
    do: source_modules

  defp normalize_catalog_source_modules!(source_modules, catalog) do
    raise ArgumentError,
          "capability source catalog #{inspect(catalog)} source_modules/0 must return a list, got: #{inspect(source_modules)}"
  end

  defp normalize_catalogs!(catalogs) when is_list(catalogs) do
    Enum.map(catalogs, &normalize_catalog!/1)
  end

  defp normalize_catalogs!(catalogs), do: raise(ArgumentError, "capability source catalogs must be a list, got: #{inspect(catalogs)}")

  defp normalize_catalog!(catalog) when is_atom(catalog) and not is_nil(catalog) do
    unless Code.ensure_loaded?(catalog) do
      raise ArgumentError, "capability source catalog #{inspect(catalog)} is not loaded"
    end

    unless function_exported?(catalog, :source_modules, 0) do
      raise ArgumentError, "capability source catalog #{inspect(catalog)} must export source_modules/0"
    end

    catalog
  end

  defp normalize_catalog!(catalog), do: raise(ArgumentError, "invalid capability source catalog: #{inspect(catalog)}")

  defp normalize_sources!(sources) when is_list(sources) do
    Enum.map(sources, &normalize_source!/1)
  end

  defp normalize_source!(source) when is_atom(source) and not is_nil(source) do
    unless Code.ensure_loaded?(source) do
      raise ArgumentError, "capability source #{inspect(source)} is not loaded"
    end

    unless function_exported?(source, :capabilities, 0) do
      raise ArgumentError, "capability source #{inspect(source)} must export capabilities/0"
    end

    source
  end

  defp normalize_source!(source), do: raise(ArgumentError, "invalid capability source: #{inspect(source)}")

  defp normalize_capabilities!(capabilities, source, callback) when is_list(capabilities) do
    Enum.map(capabilities, &normalize_capability!(&1, source, callback))
  end

  defp normalize_capabilities!(capabilities, source, callback) do
    raise ArgumentError,
          "capability source #{inspect(source)} #{callback}/0 must return a list, got: #{inspect(capabilities)}"
  end

  defp normalize_capability!(capability, _source, _callback)
       when is_binary(capability) and capability != "" do
    capability
  end

  defp normalize_capability!(capability, source, callback) do
    raise ArgumentError,
          "capability source #{inspect(source)} #{callback}/0 returned invalid capability: #{inspect(capability)}"
  end
end
