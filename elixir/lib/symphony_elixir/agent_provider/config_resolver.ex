defmodule SymphonyElixir.AgentProvider.ConfigResolver do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Config
  alias SymphonyElixir.AgentProvider.Registry
  alias SymphonyElixir.Config, as: RuntimeConfig
  alias SymphonyElixir.Workflow

  @spec current_kind(keyword()) :: String.t()
  def current_kind(opts \\ []) do
    opts
    |> Keyword.get(:kind)
    |> normalize_kind()
    |> case do
      nil ->
        workflow_kind() || Registry.default_kind()

      kind ->
        kind
    end
  end

  @spec adapter(keyword()) :: module()
  def adapter(opts \\ []) do
    if Keyword.has_key?(opts, :agent_provider_config) do
      opts
      |> effective_config()
      |> adapter_for_config()
    else
      opts
      |> current_kind()
      |> Registry.fetch!()
    end
  end

  @spec adapter_for(term()) :: module() | nil
  def adapter_for(kind) do
    kind
    |> normalize_kind()
    |> Registry.fetch()
  end

  @spec adapter_for_config(Config.t()) :: module()
  def adapter_for_config(%Config{kind: kind}) do
    Registry.fetch!(kind)
  end

  @spec effective_config(keyword()) :: Config.t()
  def effective_config(opts) when is_list(opts) do
    opts
    |> Keyword.get(:agent_provider_config)
    |> case do
      %Config{} = config -> config
      config when is_map(config) -> Config.new(config)
      _other -> current_effective_config(opts)
    end
  end

  @spec normalize_kind(term()) :: String.t() | nil
  def normalize_kind(nil), do: nil
  def normalize_kind(kind) when is_atom(kind), do: Atom.to_string(kind)

  def normalize_kind(kind) when is_binary(kind) do
    case String.trim(kind) do
      "" -> nil
      normalized -> normalized
    end
  end

  def normalize_kind(_kind), do: nil

  defp current_effective_config(opts) do
    base =
      case RuntimeConfig.settings() do
        {:ok, %{agent_provider: provider}} ->
          Config.new(provider)

        _other ->
          raw_workflow_provider_config() || %Config{kind: Registry.default_kind(), options: %{}}
      end

    base
    |> maybe_override_kind(Keyword.get(opts, :kind))
    |> maybe_override_options(Keyword.get(opts, :agent_provider_options))
  end

  defp maybe_override_kind(config, nil), do: config
  defp maybe_override_kind(config, kind), do: Config.with_kind(config, kind)

  defp maybe_override_options(config, nil), do: config
  defp maybe_override_options(config, options), do: Config.with_options(config, options)

  defp workflow_kind do
    case raw_workflow_provider() do
      provider when is_map(provider) ->
        provider
        |> Config.new()
        |> Map.get(:kind)

      _other ->
        nil
    end
  rescue
    _exception -> nil
  end

  defp raw_workflow_provider_config do
    case raw_workflow_provider() do
      provider when is_map(provider) ->
        Config.new(provider)

      _other ->
        nil
    end
  rescue
    _exception -> nil
  end

  defp raw_workflow_provider do
    case Workflow.current() do
      {:ok, %{config: config}} when is_map(config) ->
        Map.get(config, "agent_provider") || Map.get(config, :agent_provider)

      _other ->
        nil
    end
  end
end
