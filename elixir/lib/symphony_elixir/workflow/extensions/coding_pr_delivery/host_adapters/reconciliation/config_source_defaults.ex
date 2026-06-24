defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ConfigSourceDefaults do
  @moduledoc false

  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Workflow.ProfileRegistry

  @spec resolve_profile(map() | nil) :: {:ok, ProfileRegistry.resolved_profile()} | {:error, term()}
  def resolve_profile(profile), do: ProfileRegistry.resolve(profile)

  @spec tracker_lifecycle(map()) :: map() | nil
  def tracker_lifecycle(tracker) when is_map(tracker) do
    TrackerConfig.lifecycle(tracker)
  end

  def tracker_lifecycle(_tracker), do: nil
end
