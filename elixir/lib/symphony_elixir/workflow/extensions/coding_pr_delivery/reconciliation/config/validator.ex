defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Validator do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Routes

  @spec validate_supported_fields(map()) :: :ok | {:error, term()}
  def validate_supported_fields(attrs) when is_map(attrs) do
    with :ok <- validate_known_fields(attrs, Contract.root_fields()),
         :ok <- validate_section_fields(attrs, :candidates),
         :ok <- validate_section_fields(attrs, :gates),
         :ok <- validate_section_fields(attrs, :outcome_routes),
         :ok <- validate_section_fields(attrs, :thresholds) do
      :ok
    end
  end

  @spec validate_enabled_config(Config.t(), map(), map()) :: :ok | {:error, term()}
  def validate_enabled_config(%Config{enabled?: false}, _settings, _profile_context), do: :ok

  def validate_enabled_config(%Config{} = config, settings, profile_context) do
    cond do
      config.source_routes == [] ->
        {:error, :missing_source_routes}

      is_nil(Config.outcome_route(config, :ready)) ->
        {:error, :missing_ready_target_route}

      true ->
        with :ok <- Routes.validate_source_routes(config.source_routes, profile_context),
             :ok <- Routes.validate_target_routes(config, settings, profile_context) do
          :ok
        end
    end
  end

  defp validate_section_fields(attrs, section) when is_map(attrs) and is_atom(section) do
    section_key = Contract.section_key(section)
    supported_fields = Contract.section_fields(section)

    case map_value(attrs, section_key) do
      nil ->
        :ok

      section_attrs when is_map(section_attrs) ->
        validate_known_fields(section_attrs, supported_fields, section_key)

      value ->
        {:error, {:invalid_section, section_key, value}}
    end
  end

  defp validate_known_fields(attrs, supported_fields, path_prefix \\ nil) when is_map(attrs) do
    unsupported_field =
      attrs
      |> Map.keys()
      |> Enum.find(fn field ->
        not (is_binary(field) and field in supported_fields)
      end)

    case unsupported_field do
      nil -> :ok
      field -> {:error, {:unsupported_field, field_path(path_prefix, field)}}
    end
  end

  defp map_value(map, key) when is_map(map) and is_binary(key), do: Map.get(map, key)
  defp map_value(_map, _key), do: nil

  defp field_path(nil, field), do: display_field_name(field)
  defp field_path(path_prefix, field), do: path_prefix <> "." <> display_field_name(field)

  defp display_field_name(field), do: Diagnostics.field_name(field)
end
