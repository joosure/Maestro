defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.PreflightReportTemplate do
  @moduledoc """
  Builds bounded Phase 2 preflight-report fill templates.

  The template is a deterministic projection over a Phase 2 evidence plan. It
  describes the metadata operators must collect for read-only provider
  preflight commands; it does not execute those commands, call providers, read
  evidence files, mutate workflow state, approve production, or enable gates.
  """

  @schema "coding_pr_delivery.provider_preflight_report_template.v1"
  @completed_packet_schema "coding_pr_delivery.provider_preflight_report.v1"
  @phase2_schema "coding_pr_delivery.phase2_evidence_plan.v1"
  @error_code "coding_pr_delivery_preflight_report_template_invalid"
  @status_options ["passed", "blocked"]
  @allowed_evidence_ref_prefixes ["evidence/", "https://", "http://"]
  @non_claims [
    "preflight_report_does_not_collect_live_provider_evidence",
    "preflight_report_does_not_enable_production"
  ]

  @type template_result :: {:ok, map()} | {:error, map()}

  @spec build(map()) :: template_result()
  def build(phase2_plan) when is_map(phase2_plan) do
    errors = collect_phase2_plan_errors(phase2_plan)

    if errors == [] do
      {:ok, template(phase2_plan)}
    else
      {:error, invalid(errors)}
    end
  end

  def build(_phase2_plan) do
    {:error, invalid([issue("invalid_type", [], "Phase 2 evidence plan must be an object.")])}
  end

  defp collect_phase2_plan_errors(phase2_plan) do
    provider_plans = Map.get(phase2_plan, "provider_plans")

    []
    |> maybe_add(
      Map.get(phase2_plan, "schema") != @phase2_schema,
      issue("invalid_phase2_schema", ["schema"], "Preflight report templates require a Phase 2 evidence plan.")
    )
    |> maybe_add(
      not is_list(provider_plans) or provider_plans == [],
      issue("missing_provider_plans", ["provider_plans"], "Phase 2 evidence plan must include provider plans.")
    )
    |> then(fn errors ->
      if is_list(provider_plans) do
        errors ++ provider_plan_errors(provider_plans)
      else
        errors
      end
    end)
  end

  defp provider_plan_errors(provider_plans) do
    provider_plans
    |> Enum.with_index()
    |> Enum.flat_map(fn {provider_plan, index} -> provider_plan_errors(provider_plan, index) end)
  end

  defp provider_plan_errors(provider_plan, index) when is_map(provider_plan) do
    path = ["provider_plans", index]
    commands = value_at(provider_plan, ["read_only_preflight", "commands"])

    errors =
      []
      |> maybe_add(
        not non_empty_string?(Map.get(provider_plan, "template")),
        issue("required_field_missing", path ++ ["template"], "Provider plan template id is required.")
      )
      |> maybe_add(
        not is_list(commands) or commands == [],
        issue("missing_preflight_commands", path ++ ["read_only_preflight", "commands"], "Provider plan must include read-only preflight commands.")
      )

    if is_list(commands) do
      errors ++ commands_errors(commands, path ++ ["read_only_preflight", "commands"])
    else
      errors
    end
  end

  defp provider_plan_errors(_provider_plan, index) do
    [issue("invalid_type", ["provider_plans", index], "Provider plan must be an object.")]
  end

  defp commands_errors(commands, path) do
    commands
    |> Enum.with_index()
    |> Enum.flat_map(fn {command, index} -> command_errors(command, path ++ [index]) end)
  end

  defp command_errors(command, path) when is_map(command) do
    []
    |> maybe_add(
      not non_empty_string?(Map.get(command, "id")),
      issue("required_field_missing", path ++ ["id"], "Preflight command id is required.")
    )
    |> maybe_add(
      not non_empty_string?(Map.get(command, "target")),
      issue("required_field_missing", path ++ ["target"], "Preflight command target is required.")
    )
    |> maybe_add(
      not non_empty_string?(Map.get(command, "provider_kind")),
      issue("required_field_missing", path ++ ["provider_kind"], "Preflight command provider kind is required.")
    )
  end

  defp command_errors(_command, path), do: [issue("invalid_type", path, "Preflight command must be an object.")]

  defp template(phase2_plan) do
    bounded_plan = bounded_phase2_plan(phase2_plan)
    requirements = preflight_requirements(phase2_plan)

    %{
      "schema" => @schema,
      "completed_packet_schema" => @completed_packet_schema,
      "phase2_plan_id" => Map.get(phase2_plan, "plan_id"),
      "phase2_plan_kind" => Map.get(phase2_plan, "plan_kind"),
      "template_authority" => "preflight_report_shape_only",
      "does_not_collect_live_evidence" => true,
      "does_not_read_evidence_files" => true,
      "does_not_call_providers" => true,
      "does_not_mutate_workflow_state" => true,
      "does_not_approve_production" => true,
      "does_not_enable_production" => true,
      "preflight_result_requirements" => requirements,
      "required_explicit_non_claims" => @non_claims,
      "preflight_report_field_template" => %{
        "schema" => @completed_packet_schema,
        "phase2_evidence_plan" => bounded_plan,
        "provider_preflight_results" => Enum.map(requirements, &result_placeholder/1),
        "explicit_non_claims" => @non_claims
      }
    }
  end

  defp bounded_phase2_plan(phase2_plan) do
    %{
      "schema" => @phase2_schema,
      "plan_id" => Map.get(phase2_plan, "plan_id"),
      "plan_kind" => Map.get(phase2_plan, "plan_kind"),
      "plan_authority" => Map.get(phase2_plan, "plan_authority"),
      "does_not_collect_live_evidence" => Map.get(phase2_plan, "does_not_collect_live_evidence"),
      "does_not_call_providers" => Map.get(phase2_plan, "does_not_call_providers"),
      "does_not_enable_production" => Map.get(phase2_plan, "does_not_enable_production"),
      "provider_plans" => phase2_plan |> Map.get("provider_plans", []) |> Enum.map(&bounded_provider_plan/1)
    }
  end

  defp bounded_provider_plan(provider_plan) do
    %{
      "tier" => Map.get(provider_plan, "tier"),
      "template" => Map.get(provider_plan, "template"),
      "provider_matrix_entry_ids" => Map.get(provider_plan, "provider_matrix_entry_ids", []),
      "tracker_kinds" => Map.get(provider_plan, "tracker_kinds", []),
      "repo_provider_kinds" => Map.get(provider_plan, "repo_provider_kinds", []),
      "side_effect_modes" => Map.get(provider_plan, "side_effect_modes", []),
      "live_evidence_status" => Map.get(provider_plan, "live_evidence_status"),
      "read_only_preflight" => bounded_read_only_preflight(provider_plan),
      "does_not_collect_live_evidence" => Map.get(provider_plan, "does_not_collect_live_evidence"),
      "does_not_enable_production" => Map.get(provider_plan, "does_not_enable_production")
    }
  end

  defp bounded_read_only_preflight(provider_plan) do
    preflight = value_at(provider_plan, ["read_only_preflight"]) || %{}

    %{
      "status" => Map.get(preflight, "status"),
      "does_not_collect_live_evidence" => Map.get(preflight, "does_not_collect_live_evidence"),
      "does_not_mutate_workflow_state" => Map.get(preflight, "does_not_mutate_workflow_state"),
      "does_not_enable_production" => Map.get(preflight, "does_not_enable_production"),
      "commands" => preflight |> Map.get("commands", []) |> Enum.map(&bounded_command/1)
    }
  end

  defp bounded_command(command) do
    if is_map(command) do
      Map.take(command, [
        "id",
        "target",
        "provider_kind",
        "command",
        "required_env",
        "required_auth",
        "required_targets",
        "side_effect_mode",
        "requires_write_confirmation",
        "requires_destructive_flag",
        "does_not_write"
      ])
    else
      %{}
    end
  end

  defp preflight_requirements(phase2_plan) do
    phase2_plan
    |> Map.get("provider_plans", [])
    |> Enum.flat_map(&provider_preflight_requirements/1)
  end

  defp provider_preflight_requirements(provider_plan) do
    template = Map.get(provider_plan, "template")
    entry_ids = Map.get(provider_plan, "provider_matrix_entry_ids", [])

    provider_plan
    |> value_at(["read_only_preflight", "commands"])
    |> case do
      commands when is_list(commands) ->
        Enum.map(commands, &preflight_requirement(template, entry_ids, &1))

      _missing ->
        []
    end
  end

  defp preflight_requirement(template, entry_ids, command) do
    %{
      "template" => template,
      "provider_matrix_entry_ids" => entry_ids,
      "command_id" => Map.get(command, "id"),
      "target" => Map.get(command, "target"),
      "provider_kind" => Map.get(command, "provider_kind"),
      "command" => Map.get(command, "command"),
      "required_env" => Map.get(command, "required_env", []),
      "required_auth" => Map.get(command, "required_auth", []),
      "required_targets" => Map.get(command, "required_targets", []),
      "status_options" => @status_options,
      "required_side_effect_mode" => "read_only",
      "write_performed" => false,
      "production_enabled" => false,
      "raw_output_allowed" => false,
      "allowed_evidence_ref_prefixes" => @allowed_evidence_ref_prefixes,
      "evidence_files" => evidence_files(template, Map.get(command, "id")),
      "fields_to_complete" => ["status", "ran_at", "evidence_files"],
      "blocked_fields_to_complete" => ["blocker_code", "missing_prerequisites"]
    }
  end

  defp result_placeholder(requirement) do
    %{
      "template" => Map.get(requirement, "template"),
      "command_id" => Map.get(requirement, "command_id"),
      "target" => Map.get(requirement, "target"),
      "provider_kind" => Map.get(requirement, "provider_kind"),
      "status" => "fill-passed-or-blocked",
      "ran_at" => "fill-iso8601-timestamp",
      "side_effect_mode" => "read_only",
      "write_performed" => false,
      "production_enabled" => false,
      "evidence_files" => Map.get(requirement, "evidence_files", []),
      "blocker_code" => "fill-when-blocked",
      "missing_prerequisites" => []
    }
  end

  defp evidence_files(template, command_id) do
    ["evidence/preflight/#{template}/#{command_id}.md"]
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery preflight report template is invalid.",
      errors: errors
    }
  end

  defp issue(code, path, message) do
    %{
      code: code,
      path: path,
      message: message
    }
  end

  defp maybe_add(errors, true, issue), do: errors ++ [issue]
  defp maybe_add(errors, false, _issue), do: errors

  defp value_at(map, path) when is_map(map) and is_list(path) do
    Enum.reduce_while(path, map, fn key, current ->
      if is_map(current) and Map.has_key?(current, key) do
        {:cont, Map.get(current, key)}
      else
        {:halt, nil}
      end
    end)
  end

  defp value_at(_map, _path), do: nil

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""
end
