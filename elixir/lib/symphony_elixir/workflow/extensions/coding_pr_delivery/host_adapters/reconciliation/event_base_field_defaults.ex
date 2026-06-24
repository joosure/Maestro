defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.EventBaseFieldDefaults do
  @moduledoc false

  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Workflow.ProfileRegistry

  @spec repo_provider_kind(map()) :: String.t() | nil
  def repo_provider_kind(settings) when is_map(settings) do
    settings
    |> repo_config()
    |> case do
      repo when is_map(repo) -> RepoProvider.current_kind(repo)
      _repo -> nil
    end
  end

  def repo_provider_kind(_settings), do: nil

  @spec tracker_kind(map()) :: String.t() | nil
  def tracker_kind(settings) when is_map(settings) do
    settings
    |> tracker_config()
    |> case do
      tracker when is_map(tracker) -> TrackerConfig.kind(tracker)
      _tracker -> nil
    end
  end

  def tracker_kind(_settings), do: nil

  @spec profile_context(map()) :: {:ok, map()} | {:error, term()}
  def profile_context(settings) when is_map(settings) do
    settings
    |> workflow_profile()
    |> ProfileRegistry.resolve()
  end

  def profile_context(_settings), do: {:error, :missing_workflow_profile}

  defp workflow_profile(%{workflow: %{profile: profile}}) when is_map(profile), do: profile
  defp workflow_profile(%{"workflow" => %{"profile" => profile}}) when is_map(profile), do: profile

  defp workflow_profile(settings) when is_map(settings) do
    case workflow_config(settings) do
      %{profile: profile} when is_map(profile) -> profile
      %{"profile" => profile} when is_map(profile) -> profile
      _workflow -> nil
    end
  end

  defp repo_config(%{repo: repo}), do: repo
  defp repo_config(%{"repo" => repo}), do: repo
  defp repo_config(_settings), do: nil

  defp tracker_config(%{tracker: tracker}), do: tracker
  defp tracker_config(%{"tracker" => tracker}), do: tracker
  defp tracker_config(_settings), do: nil

  defp workflow_config(%{workflow: workflow}), do: workflow
  defp workflow_config(%{"workflow" => workflow}), do: workflow
  defp workflow_config(_settings), do: nil
end
