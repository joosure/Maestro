defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Source do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ConfigSourceDefaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Contract

  @spec resolve_profile_context(map(), Config.profile_context() | nil) ::
          {:ok, Config.profile_context()} | {:error, term()}
  def resolve_profile_context(_settings, %{module: module} = profile_context) when is_atom(module) do
    {:ok, profile_context}
  end

  def resolve_profile_context(settings, _profile_context) do
    settings
    |> workflow_profile()
    |> ConfigSourceDefaults.resolve_profile()
  end

  @spec extension_attrs(map()) :: {:ok, map()} | {:error, term()}
  def extension_attrs(settings) when is_map(settings) do
    case workflow_reconciliation(settings) |> map_value(Contract.config_key()) do
      nil -> {:ok, %{}}
      attrs when is_map(attrs) -> {:ok, attrs}
      attrs -> {:error, {:invalid_coding_pr_delivery_reconciliation_config, attrs}}
    end
  end

  @spec policy_by_route_key(map()) :: map() | nil
  def policy_by_route_key(settings) when is_map(settings) do
    settings
    |> settings_tracker()
    |> tracker_lifecycle()
    |> map_value(Contract.settings_key(:policy_by_route_key))
  end

  defp settings_tracker(%{tracker: tracker}), do: tracker
  defp settings_tracker(settings) when is_map(settings), do: map_value(settings, Contract.settings_key(:tracker))

  defp tracker_lifecycle(tracker) when is_map(tracker) do
    case ConfigSourceDefaults.tracker_lifecycle(tracker) do
      lifecycle when is_map(lifecycle) -> lifecycle
      _lifecycle -> map_value(tracker, Contract.settings_key(:lifecycle)) || %{}
    end
  end

  defp tracker_lifecycle(_tracker), do: %{}

  defp workflow_profile(%{workflow: %{profile: profile}}) when is_map(profile), do: profile

  defp workflow_profile(settings) when is_map(settings) do
    case map_value(settings, Contract.settings_key(:workflow)) do
      workflow when is_map(workflow) ->
        case map_value(workflow, Contract.settings_key(:profile)) do
          profile when is_map(profile) -> profile
          _profile -> nil
        end

      _workflow ->
        nil
    end
  end

  defp workflow_profile(_settings), do: nil

  defp workflow_reconciliation(%{workflow: %{reconciliation: reconciliation}})
       when is_map(reconciliation),
       do: reconciliation

  defp workflow_reconciliation(settings) when is_map(settings) do
    case map_value(settings, Contract.settings_key(:workflow)) do
      workflow when is_map(workflow) ->
        case map_value(workflow, Contract.settings_key(:reconciliation)) do
          reconciliation when is_map(reconciliation) -> reconciliation
          _reconciliation -> %{}
        end

      _workflow ->
        %{}
    end
  end

  defp map_value(map, key) when is_map(map) and is_binary(key), do: Map.get(map, key)
  defp map_value(_map, _key), do: nil
end
