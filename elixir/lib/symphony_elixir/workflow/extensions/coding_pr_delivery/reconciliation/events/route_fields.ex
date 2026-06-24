defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.RouteFields do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.EventBaseFieldDefaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.Fields
  alias SymphonyElixir.Workflow.IssueContext
  alias SymphonyElixir.Workflow.RouteFacts
  alias SymphonyElixir.Workflow.RouteRef

  @spec source(RouteFacts.t(), map(), Issue.t()) :: map()
  def source(%RouteFacts{} = route_facts, settings, %Issue{} = issue) when is_map(settings) do
    settings
    |> route_ref(issue, route_facts.route_key)
    |> case do
      {:ok, route_ref} -> prefixed(:source, route_ref)
      {:error, _reason} -> %{Fields.source_workflow_route_key() => route_key_name(route_facts.route_key)}
    end
  end

  @spec target(RouteRef.t() | term()) :: map()
  def target(%RouteRef{} = route_ref), do: prefixed(:target, route_ref)
  def target(_route_ref), do: %{}

  @spec route_ref_maps([RouteRef.t()]) :: [map()]
  def route_ref_maps(route_refs) when is_list(route_refs), do: Enum.map(route_refs, &route_ref_map/1)

  defp route_ref(settings, %Issue{} = issue, route_key) do
    profile_context =
      if issue_workflow_profile?(issue) do
        IssueContext.profile_context(issue)
      else
        profile_context(settings)
      end

    RouteRef.new(profile_context, route_key)
  end

  defp profile_context(settings) do
    case EventBaseFieldDefaults.profile_context(settings) do
      {:ok, profile_context} -> profile_context
      {:error, _reason} -> %{}
    end
  end

  defp issue_workflow_profile?(%Issue{} = issue) do
    issue
    |> IssueContext.workflow_map(%{})
    |> Map.get(:profile)
    |> case do
      profile when is_map(profile) -> map_size(profile) > 0
      _profile -> false
    end
  end

  defp prefixed(:source, %RouteRef{} = route_ref) do
    %{
      Fields.source_workflow_profile() => route_ref.profile_kind,
      Fields.source_workflow_profile_version() => route_ref.profile_version,
      Fields.source_workflow_route_key() => route_key_name(route_ref.route_key)
    }
  end

  defp prefixed(:target, %RouteRef{} = route_ref) do
    %{
      Fields.target_workflow_profile() => route_ref.profile_kind,
      Fields.target_workflow_profile_version() => route_ref.profile_version,
      Fields.target_workflow_route_key() => route_key_name(route_ref.route_key)
    }
  end

  defp route_ref_map(%RouteRef{} = route_ref) do
    %{
      Fields.route_ref_profile() => route_ref.profile_kind,
      Fields.route_ref_profile_version() => route_ref.profile_version,
      Fields.route_ref_route_key() => route_key_name(route_ref.route_key)
    }
  end

  defp route_key_name(route_key) when is_atom(route_key), do: Atom.to_string(route_key)
  defp route_key_name(route_key) when is_binary(route_key), do: route_key
  defp route_key_name(_route_key), do: nil
end
