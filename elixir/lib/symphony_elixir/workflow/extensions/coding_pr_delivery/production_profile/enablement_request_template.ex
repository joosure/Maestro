defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EnablementRequestTemplate do
  @moduledoc """
  Builds production enablement-request fill templates from ready review decisions.

  The template is the handoff between a reviewer-approved decision and a human
  production switch request. It validates the review decision boundary and
  projects scoped request fields, but it does not apply settings, call
  providers, mutate workflow state, or enable production gates.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  @schema "coding_pr_delivery.production_enablement_request_template.v1"
  @completed_packet_schema "coding_pr_delivery.production_enablement_request.v1"
  @error_code "coding_pr_delivery_enablement_request_template_invalid"
  @review_decision_schema "coding_pr_delivery.production_review_decision.v1"
  @side_effect_modes ["read_only", "shadow_no_write", "review_handoff_write", "ready_to_land_write"]

  @type result :: {:ok, map()} | {:error, map()}

  @spec build(map(), keyword()) :: result()
  def build(review_decision, opts \\ [])

  def build(review_decision, opts) when is_map(review_decision) and is_list(opts) do
    selected_ids = selected_entry_ids(review_decision, opts)
    selected_entries = selected_entries(review_decision, selected_ids)
    selected_mode = selected_side_effect_mode(selected_entries, opts)

    errors =
      []
      |> collect_review_decision(review_decision)
      |> collect_selected_entries(review_decision, selected_ids, selected_entries)
      |> collect_selected_mode(selected_mode, selected_entries)

    if errors == [] do
      {:ok, template(review_decision, selected_entries, selected_mode, opts)}
    else
      {:error, invalid(errors)}
    end
  end

  def build(_review_decision, opts) when is_list(opts) do
    {:error, invalid([issue("invalid_type", [], "Review decision must be an object.")])}
  end

  def build(_review_decision, _opts) do
    {:error, invalid([issue("invalid_options", [], "Enablement request template options must be a keyword list.")])}
  end

  defp collect_review_decision(errors, decision) do
    blockers = value_at(decision, ["blockers"])

    errors
    |> maybe_add(
      value_at(decision, ["schema"]) != @review_decision_schema,
      issue("invalid_review_decision_schema", ["review_decision", "schema"], "Review decision schema is invalid.")
    )
    |> maybe_add(
      value_at(decision, ["status"]) != "ready_for_approval",
      issue("review_decision_not_ready", ["review_decision", "status"], "Enablement template requires a ready review decision.")
    )
    |> maybe_add(
      blockers != [],
      issue("review_decision_blocked", ["review_decision", "blockers"], "Enablement template requires a review decision with no blockers.")
    )
    |> maybe_add(
      value_at(decision, ["does_not_enable_production"]) != true,
      issue("review_decision_side_effect_boundary", ["review_decision", "does_not_enable_production"], "Review decision must be non-mutating.")
    )
    |> maybe_add(
      value_at(decision, ["raw_evidence_payload_included"]) != false,
      issue("raw_evidence_payload_present", ["review_decision", "raw_evidence_payload_included"], "Review decision must not include raw evidence payloads.")
    )
    |> maybe_add(
      not non_empty_string?(value_at(decision, ["profile_instance_id"])),
      issue("required_field_missing", ["review_decision", "profile_instance_id"], "Review decision must name the profile instance.")
    )
    |> maybe_add(
      not is_list(value_at(decision, ["provider_entries"])) or value_at(decision, ["provider_entries"]) == [],
      issue("required_field_missing", ["review_decision", "provider_entries"], "Review decision must include provider entries.")
    )
  end

  defp collect_selected_entries(errors, review_decision, selected_ids, selected_entries) do
    decision_entry_ids =
      review_decision
      |> provider_entries()
      |> Enum.map(&Map.get(&1, "entry_id"))

    errors
    |> maybe_add(
      selected_ids == [],
      issue("required_field_missing", ["provider_matrix_entry_ids"], "Enablement template requires at least one provider entry.")
    )
    |> then(fn errors ->
      selected_ids
      |> Enum.reject(&(&1 in decision_entry_ids))
      |> Enum.map(fn entry_id ->
        issue("unknown_provider_matrix_entry", ["provider_matrix_entry_ids"], "Selected provider entry is not present in the review decision.", %{provider_matrix_entry_id: entry_id})
      end)
      |> then(&(errors ++ &1))
    end)
    |> maybe_add(
      selected_ids != [] and selected_entries == [],
      issue("required_field_missing", ["provider_matrix_entry_ids"], "Selected provider entries must resolve to review decision entries.")
    )
  end

  defp collect_selected_mode(errors, mode, selected_entries) do
    modes =
      selected_entries
      |> Enum.map(&Map.get(&1, "side_effect_mode"))
      |> Enum.uniq()

    errors
    |> maybe_add(
      not non_empty_string?(mode),
      issue("ambiguous_side_effect_mode", ["side_effect_mode"], "Selected provider entries require one explicit side-effect mode.")
    )
    |> maybe_add(
      non_empty_string?(mode) and mode not in @side_effect_modes,
      issue("invalid_side_effect_mode", ["side_effect_mode"], "Selected side-effect mode is unsupported.", %{allowed_values: @side_effect_modes})
    )
    |> maybe_add(
      length(modes) > 1 and non_empty_string?(mode),
      issue("mixed_side_effect_modes", ["provider_matrix_entry_ids"], "Selected provider entries must share one reviewed side-effect mode.")
    )
    |> maybe_add(
      length(modes) == 1 and non_empty_string?(mode) and hd(modes) != mode,
      issue("side_effect_mode_mismatch", ["side_effect_mode"], "Selected side-effect mode must match the reviewed provider entry mode.", %{
        reviewed_side_effect_mode: hd(modes),
        selected_side_effect_mode: mode
      })
    )
  end

  defp template(review_decision, selected_entries, selected_mode, opts) do
    selected_ids = Enum.map(selected_entries, &Map.get(&1, "entry_id"))

    %{
      "schema" => @schema,
      "completed_packet_schema" => @completed_packet_schema,
      "profile_instance_id" => value_at(review_decision, ["profile_instance_id"]),
      "review_packet_id" => value_at(review_decision, ["review_packet_id"]),
      "template_authority" => "enablement_request_shape_only",
      "does_not_enable_production" => true,
      "review_decision" => review_decision,
      "selected_provider_entries" => selected_entries,
      "enablement_request_field_template" => %{
        "enablement_request_id" => "fill-enable-request-id",
        "requested_by" => "fill-requester",
        "requested_at" => "fill-requested-at",
        "review_decision" => review_decision,
        "scope" => scope(selected_ids, selected_mode, opts),
        "gate_values" => gate_values(selected_mode),
        "observation_window" => observation_window(selected_mode, opts),
        "rollback" => rollback(selected_entries),
        "acknowledged_non_claims" => non_claims(selected_entries),
        "approvals" => [],
        "activation_control" => %{
          "change_ticket" => "fill-change-ticket",
          "requires_operator_apply" => true,
          "applies_immediately" => false
        }
      },
      "fields_to_complete" => [
        "enablement_request_id",
        "requested_by",
        "requested_at",
        "scope.repositories",
        "approvals",
        "activation_control.change_ticket"
      ]
    }
  end

  defp selected_entry_ids(review_decision, opts) do
    case Keyword.get(opts, :provider_matrix_entry_ids) do
      ids when is_list(ids) ->
        Enum.filter(ids, &non_empty_string?/1)

      id when is_binary(id) ->
        [id]

      _missing ->
        review_decision
        |> provider_entries()
        |> Enum.map(&Map.get(&1, "entry_id"))
        |> Enum.filter(&non_empty_string?/1)
    end
  end

  defp selected_entries(review_decision, selected_ids) do
    review_decision
    |> provider_entries()
    |> Enum.filter(&(Map.get(&1, "entry_id") in selected_ids))
  end

  defp selected_side_effect_mode(selected_entries, opts) do
    case Keyword.get(opts, :side_effect_mode) do
      mode when is_binary(mode) ->
        mode

      _missing ->
        selected_entries
        |> Enum.map(&Map.get(&1, "side_effect_mode"))
        |> Enum.uniq()
        |> case do
          [mode] -> mode
          _ambiguous -> nil
        end
    end
  end

  defp scope(selected_ids, selected_mode, opts) do
    %{
      "environment" => Keyword.get(opts, :environment, "production"),
      "repositories" => Keyword.get(opts, :repositories, ["fill-repository"]),
      "provider_matrix_entry_ids" => selected_ids,
      "side_effect_mode" => selected_mode
    }
  end

  defp gate_values("ready_to_land_write") do
    %{
      Gates.transition_readiness_required_gate_key() => true,
      Gates.enabled_gate_key() => true
    }
  end

  defp gate_values(_mode) do
    %{
      Gates.transition_readiness_required_gate_key() => false,
      Gates.enabled_gate_key() => true
    }
  end

  defp observation_window("shadow_no_write", opts) do
    %{
      "duration_days" => Keyword.get(opts, :observation_days, 14),
      "success_criteria" => ["zero canonical writes", "zero shadow isolation violations"]
    }
  end

  defp observation_window(_mode, opts) do
    %{
      "duration_days" => Keyword.get(opts, :observation_days, 14),
      "success_criteria" => ["zero unexpected transitions", "zero rollback violations"]
    }
  end

  defp rollback(selected_entries) do
    %{
      "owner" => rollback_owner(selected_entries),
      "disable_gates" => [
        Gates.transition_readiness_required_gate_key(),
        Gates.enabled_gate_key()
      ],
      "verified" => true
    }
  end

  defp rollback_owner(selected_entries) do
    selected_entries
    |> Enum.map(&value_at(&1, ["rollback", "owner"]))
    |> Enum.find("workflow-runtime", &non_empty_string?/1)
  end

  defp non_claims(selected_entries) do
    selected_entries
    |> Enum.flat_map(&Map.get(&1, "non_claims", []))
    |> Enum.filter(&non_empty_string?/1)
    |> Enum.uniq()
  end

  defp provider_entries(review_decision) do
    case value_at(review_decision, ["provider_entries"]) do
      entries when is_list(entries) -> entries
      _missing -> []
    end
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery enablement request template is invalid.",
      errors: errors
    }
  end

  defp maybe_add(errors, true, issue), do: errors ++ [issue]
  defp maybe_add(errors, false, _issue), do: errors

  defp issue(code, path, message, extra \\ %{}) do
    Map.merge(
      %{
        code: code,
        path: path,
        message: message
      },
      extra
    )
  end

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp value_at(map, path) when is_map(map) and is_list(path) do
    Enum.reduce_while(path, map, fn key, current ->
      cond do
        is_map(current) and Map.has_key?(current, key) ->
          {:cont, Map.get(current, key)}

        is_map(current) and is_atom(key) and Map.has_key?(current, Atom.to_string(key)) ->
          {:cont, Map.get(current, Atom.to_string(key))}

        true ->
          {:halt, nil}
      end
    end)
  end

  defp value_at(_map, _path), do: nil
end
