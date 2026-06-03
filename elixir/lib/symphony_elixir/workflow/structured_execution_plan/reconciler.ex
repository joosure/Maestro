defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler do
  @moduledoc """
  Recomputes structured execution plan item status from immutable evidence refs.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.StatusMachine

  @staleable_evidence_kinds ~w(repo_diff repo_read_change_proposal_checks repo_read_change_proposal_discussion tracker_upsert_workpad)
  @repo_change_evidence_kinds ~w(repo_commit repo_push)

  @spec reconcile(map()) :: {:ok, map()} | {:error, map()}
  def reconcile(plan) when is_map(plan) do
    items = Map.get(plan, "items", [])

    if is_list(items) do
      {:ok, Map.put(plan, "items", Enum.map(items, &reconcile_item(&1, items)))}
    else
      {:error, %{code: "schema_invalid", message: "Structured execution plan items must be an array."}}
    end
  end

  def reconcile(_plan), do: {:error, %{code: "schema_invalid", message: "Structured execution plan must be an object."}}

  @spec satisfied?(map()) :: boolean()
  def satisfied?(item) when is_map(item), do: requirements_satisfied?(item)
  def satisfied?(_item), do: false

  defp reconcile_item(item, all_items) when is_map(item) do
    cond do
      Map.get(item, "status") == "superseded" ->
        item

      stale?(item, all_items) ->
        maybe_put_status(item, "in_progress")

      requirements_satisfied?(item) ->
        maybe_put_status(item, "complete")

      true ->
        item
    end
  end

  defp reconcile_item(item, _all_items), do: item

  defp maybe_put_status(%{"status" => status} = item, status), do: item

  defp maybe_put_status(%{"status" => from_status} = item, to_status) do
    if StatusMachine.allowed_item_transition?(from_status, to_status) do
      Map.put(item, "status", to_status)
    else
      item
    end
  end

  defp requirements_satisfied?(%{"evidence_requirements" => requirements, "evidence_refs" => refs})
       when is_list(requirements) and is_list(refs) do
    requirements != [] and Enum.all?(requirements, &requirement_satisfied?(&1, refs))
  end

  defp requirements_satisfied?(_item), do: false

  defp requirement_satisfied?(%{"evidence_kind" => evidence_kind} = requirement, refs) do
    Enum.any?(refs, &ref_satisfies_requirement?(&1, requirement, evidence_kind))
  end

  defp requirement_satisfied?(_requirement, _refs), do: false

  defp ref_satisfies_requirement?(%{"evidence_kind" => evidence_kind, "source" => source, "payload" => payload}, requirement, evidence_kind)
       when is_map(payload) do
    source in Map.get(requirement, "trust_classes", []) and
      required_fields_present?(payload, Map.get(requirement, "required_fields", [])) and
      evidence_kind_valid?(evidence_kind, payload)
  end

  defp ref_satisfies_requirement?(_ref, _requirement, _evidence_kind), do: false

  defp required_fields_present?(payload, required_fields) when is_map(payload) and is_list(required_fields) do
    Enum.all?(required_fields, &present?(Map.get(payload, &1)))
  end

  defp required_fields_present?(_payload, _required_fields), do: false

  defp evidence_kind_valid?("repo_push", %{"head_sha" => head_sha, "published_head_sha" => published_head_sha})
       when is_binary(head_sha) and is_binary(published_head_sha),
       do: head_sha == published_head_sha

  defp evidence_kind_valid?("repo_push", _payload), do: false
  defp evidence_kind_valid?("repo_diff", %{"check" => true}), do: true
  defp evidence_kind_valid?("repo_diff", _payload), do: false
  defp evidence_kind_valid?("repo_create_or_update_change_proposal", payload), do: provider_change_proposal_url?(Map.get(payload, "url"))
  defp evidence_kind_valid?("repo_read_change_proposal_checks", payload), do: Map.get(payload, "status") in ["passed", "not_required"]
  defp evidence_kind_valid?("repo_read_change_proposal_discussion", payload), do: Map.get(payload, "status") in ["clear", "not_required"]
  defp evidence_kind_valid?("tracker_attach_change_proposal", payload), do: Map.get(payload, "linked_to_tracker") == true
  defp evidence_kind_valid?(_evidence_kind, _payload), do: true

  defp stale?(item, all_items) do
    item_evidence_kinds = item_requirement_kinds(item)

    Enum.any?(item_evidence_kinds, &(&1 in @staleable_evidence_kinds)) and
      latest_repo_change_at(all_items) |> newer_than?(latest_item_requirement_evidence_at(item))
  end

  defp latest_repo_change_at(items) when is_list(items) do
    items
    |> Enum.flat_map(&Map.get(&1, "evidence_refs", []))
    |> Enum.filter(&(Map.get(&1, "evidence_kind") in @repo_change_evidence_kinds))
    |> latest_observed_at()
  end

  defp latest_item_requirement_evidence_at(item) do
    requirement_kinds = item_requirement_kinds(item)

    item
    |> Map.get("evidence_refs", [])
    |> Enum.filter(&(Map.get(&1, "evidence_kind") in requirement_kinds))
    |> latest_observed_at()
  end

  defp latest_observed_at(refs) do
    refs
    |> Enum.flat_map(fn ref ->
      case DateTime.from_iso8601(Map.get(ref, "observed_at", "")) do
        {:ok, datetime, _offset} -> [datetime]
        _other -> []
      end
    end)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp newer_than?(nil, _right), do: false
  defp newer_than?(_left, nil), do: true
  defp newer_than?(left, right), do: DateTime.compare(left, right) == :gt

  defp item_requirement_kinds(item) do
    item
    |> Map.get("evidence_requirements", [])
    |> Enum.flat_map(fn
      %{"evidence_kind" => evidence_kind} when is_binary(evidence_kind) -> [evidence_kind]
      _requirement -> []
    end)
  end

  defp provider_change_proposal_url?(url) when is_binary(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] and is_binary(uri.host) and not String.contains?(uri.path || "", "/compare/")
  end

  defp provider_change_proposal_url?(_url), do: false

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_boolean(value), do: true
  defp present?(value) when is_integer(value), do: true
  defp present?(value) when is_list(value), do: value != []
  defp present?(value), do: not is_nil(value)
end
