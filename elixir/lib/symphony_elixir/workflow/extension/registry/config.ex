defmodule SymphonyElixir.Workflow.Extension.Registry.Config do
  @moduledoc """
  Production application configuration boundary for workflow extensions.

  Root application configuration is source-only. Direct extension module
  injection remains a function-level test or explicit assembly option, not a
  production configuration shape.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.Registry.Error

  @app :symphony_elixir
  @config_key :workflow_runtime_extensions
  @app_config_keys [:sources]

  @spec configured_sources() :: {:ok, [module()]} | {:error, map()}
  def configured_sources do
    with {:ok, config} <- configured_runtime_extensions(),
         {:ok, sources} <- configured_sources(config) do
      {:ok, sources}
    end
  end

  defp configured_runtime_extensions do
    config = Application.get_env(@app, @config_key, [])
    unsupported_keys = if Keyword.keyword?(config), do: Keyword.keys(config) -- @app_config_keys, else: []

    cond do
      not Keyword.keyword?(config) ->
        {:error, Error.invalid(:registry, :configured_registry_not_keyword, value_type: Diagnostics.type_atom(config))}

      unsupported_keys != [] ->
        reason = if :entries in unsupported_keys, do: :configured_entries_not_supported, else: :configured_registry_keys_not_supported
        {:error, Error.invalid(:registry, reason, keys: Enum.map(unsupported_keys, &inspect/1))}

      true ->
        {:ok, config}
    end
  end

  defp configured_sources(config) do
    case Keyword.get(config, :sources, []) do
      sources when is_list(sources) ->
        {:ok, sources}

      sources ->
        {:error, Error.invalid(:registry, :configured_sources_not_list, value_type: Diagnostics.type_atom(sources))}
    end
  end
end
