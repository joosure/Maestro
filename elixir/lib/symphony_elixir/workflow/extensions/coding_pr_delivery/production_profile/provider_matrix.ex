defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ProviderMatrix do
  @moduledoc """
  Admission checks for Coding PR Delivery production provider-matrix claims.

  This module is intentionally pure. It validates review-packet or Phase 2
  evidence metadata before a production claim is accepted; it does not enable a
  workflow profile or call providers.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile.Contract, as: ProfileContract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Contract, as: ReconciliationConfigContract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  @error_code "coding_pr_delivery_provider_matrix_invalid"
  @shadow_mode OneShotContract.shadow_mode()
  @side_effect_modes [
    "read_only",
    @shadow_mode,
    "review_handoff_write",
    "ready_to_land_write"
  ]
  @topology_modes ["singleton", "distributed_lock", "external_queue"]
  @typed_tool_sections ["tracker", "repo_core", "repo_provider"]
  @gate_aliases ["structured_plan_gates", "enabled_gates", "gates"]

  @type validation_result :: {:ok, map()} | {:error, map()}

  @spec side_effect_modes() :: [String.t()]
  def side_effect_modes, do: @side_effect_modes

  @spec validate_claim(map()) :: validation_result()
  def validate_claim(claim) when is_map(claim) do
    errors =
      []
      |> collect_required_string(claim, ["profile_instance_id"])
      |> collect_provider_matrix(claim)

    if errors == [] do
      {:ok, normalize_claim(claim)}
    else
      {:error, invalid(errors)}
    end
  end

  def validate_claim(_claim) do
    {:error, invalid([issue("invalid_type", [], "Production provider-matrix claim must be an object.")])}
  end

  @spec validate_entry(map()) :: validation_result()
  def validate_entry(entry) when is_map(entry) do
    errors = entry_errors(entry, [])

    if errors == [] do
      {:ok, normalize_entry(entry)}
    else
      {:error, invalid(errors)}
    end
  end

  def validate_entry(_entry) do
    {:error, invalid([issue("invalid_type", [], "Provider-matrix entry must be an object.")])}
  end

  defp collect_provider_matrix(errors, claim) do
    case value_at(claim, ["provider_matrix"]) do
      entries when is_list(entries) and entries != [] ->
        entries
        |> Enum.with_index()
        |> Enum.flat_map(fn {entry, index} -> entry_errors(entry, ["provider_matrix", index]) end)
        |> then(&(errors ++ &1))

      entries when is_list(entries) ->
        errors ++ [issue("required_field_missing", ["provider_matrix"], "Provider matrix must contain at least one entry.")]

      _missing_or_invalid ->
        errors ++ [issue("required_field_missing", ["provider_matrix"], "Provider matrix must be a non-empty array.")]
    end
  end

  defp entry_errors(entry, path) when is_map(entry) do
    []
    |> collect_required_string(entry, path ++ ["id"])
    |> collect_workflow_profile(entry, path)
    |> collect_provider_kind(entry, path, "tracker")
    |> collect_provider_kind(entry, path, "repo_provider")
    |> collect_provider_kind(entry, path, "agent_provider")
    |> collect_required_string(entry, path ++ ["repository_class"])
    |> collect_required_string(entry, path ++ ["candidate_discovery"])
    |> collect_candidate_discovery(entry, path)
    |> collect_side_effect_mode(entry, path)
    |> collect_topology(entry, path)
    |> collect_gates(entry, path)
    |> collect_typed_tool_inventory(entry, path)
    |> collect_string_list(entry, path ++ ["evidence_files"], "Evidence files must be a non-empty string array.")
    |> collect_required_map(entry, path ++ ["recovery"])
    |> collect_required_string(entry, path ++ ["recovery", "model"])
    |> collect_required_map(entry, path ++ ["rollback"])
    |> collect_required_string(entry, path ++ ["rollback", "owner"])
    |> collect_rollback(entry, path)
    |> collect_mode_specific(entry, path)
  end

  defp entry_errors(_entry, path), do: [issue("invalid_type", path, "Provider-matrix entry must be an object.")]

  defp collect_workflow_profile(errors, entry, path) do
    workflow_profile = value_at(entry, ["workflow_profile"])

    errors
    |> collect_required_map(entry, path ++ ["workflow_profile"])
    |> maybe_add(
      value_at(workflow_profile, ["kind"]) != ProfileContract.kind(),
      issue("invalid_workflow_profile", path ++ ["workflow_profile", "kind"], "Workflow profile kind must be coding_pr_delivery.")
    )
    |> maybe_add(
      value_at(workflow_profile, ["version"]) != ProfileContract.version(),
      issue("invalid_workflow_profile", path ++ ["workflow_profile", "version"], "Workflow profile version is unsupported.")
    )
  end

  defp collect_provider_kind(errors, entry, path, provider_key) do
    errors
    |> collect_required_map(entry, path ++ [provider_key])
    |> collect_required_string(entry, path ++ [provider_key, "kind"])
  end

  defp collect_candidate_discovery(errors, entry, path) do
    value = value_at(entry, ["candidate_discovery"])

    maybe_add(
      errors,
      is_binary(value) and value not in ReconciliationConfigContract.candidate_discovery_modes(),
      issue("invalid_candidate_discovery", path ++ ["candidate_discovery"], "Candidate discovery mode is unsupported.", allowed_values: ReconciliationConfigContract.candidate_discovery_modes())
    )
  end

  defp collect_side_effect_mode(errors, entry, path) do
    value = value_at(entry, ["side_effect_mode"])

    cond do
      not non_empty_string?(value) ->
        errors ++ [issue("required_field_missing", path ++ ["side_effect_mode"], "Side-effect mode is required.")]

      value not in @side_effect_modes ->
        errors ++ [issue("invalid_side_effect_mode", path ++ ["side_effect_mode"], "Side-effect mode is unsupported.", allowed_values: @side_effect_modes)]

      true ->
        errors
    end
  end

  defp collect_topology(errors, entry, path) do
    topology = value_at(entry, ["deployment_topology"])
    mode = value_at(topology, ["mode"])

    errors
    |> collect_required_map(entry, path ++ ["deployment_topology"])
    |> maybe_add(
      not non_empty_string?(mode),
      issue("required_field_missing", path ++ ["deployment_topology", "mode"], "Deployment topology mode is required.")
    )
    |> maybe_add(
      is_binary(mode) and mode not in @topology_modes,
      issue("invalid_topology_mode", path ++ ["deployment_topology", "mode"], "Deployment topology mode is unsupported.", allowed_values: @topology_modes)
    )
    |> collect_topology_proof(topology, mode, path)
  end

  defp collect_topology_proof(errors, topology, "singleton", path) do
    maybe_add(
      errors,
      not non_empty_string?(value_at(topology, ["readiness_check"])),
      issue("required_field_missing", path ++ ["deployment_topology", "readiness_check"], "Field must be a non-empty string.")
    )
  end

  defp collect_topology_proof(errors, topology, mode, path) when mode in ["distributed_lock", "external_queue"] do
    maybe_add(
      errors,
      not non_empty_string?(value_at(topology, ["ownership_proof"])),
      issue("required_field_missing", path ++ ["deployment_topology", "ownership_proof"], "Field must be a non-empty string.")
    )
  end

  defp collect_topology_proof(errors, _topology, _mode, _path), do: errors

  defp collect_gates(errors, entry, path) do
    gates = gate_map(entry)

    errors
    |> maybe_add(
      not is_map(gates),
      issue("required_field_missing", path ++ ["structured_plan_gates"], "Structured execution-plan gate values are required.")
    )
    |> collect_gate_values(gates, path)
  end

  defp collect_gate_values(errors, gates, path) when is_map(gates) do
    missing_or_invalid =
      Enum.flat_map(Gates.gate_keys(), fn key ->
        case Map.fetch(gates, key) do
          {:ok, value} when is_boolean(value) ->
            []

          {:ok, _value} ->
            [issue("invalid_gate_value", path ++ ["structured_plan_gates", key], "Structured execution-plan gate value must be boolean.")]

          :error ->
            [issue("required_field_missing", path ++ ["structured_plan_gates", key], "Structured execution-plan gate value is required.")]
        end
      end)

    unknown =
      gates
      |> Map.keys()
      |> Enum.reject(&(&1 in Gates.gate_keys()))
      |> Enum.map(fn key -> issue("unknown_gate_key", path ++ ["structured_plan_gates", key], "Structured execution-plan gate key is not supported.") end)

    errors ++ missing_or_invalid ++ unknown
  end

  defp collect_gate_values(errors, _gates, _path), do: errors

  defp collect_typed_tool_inventory(errors, entry, path) do
    inventory = value_at(entry, ["typed_tool_inventory"]) || value_at(entry, ["typed_tool_requirements"])

    errors =
      maybe_add(
        errors,
        not is_map(inventory),
        issue("required_field_missing", path ++ ["typed_tool_inventory"], "Typed tool inventory is required.")
      )

    if is_map(inventory) do
      Enum.reduce(@typed_tool_sections, errors, fn section, acc ->
        maybe_add(
          acc,
          not string_list?(value_at(inventory, [section])) or value_at(inventory, [section]) == [],
          issue("required_field_missing", path ++ ["typed_tool_inventory", section], "Typed tool inventory section must be a non-empty string array.")
        )
      end)
    else
      errors
    end
  end

  defp collect_rollback(errors, entry, path) do
    readiness_gate = value_at(entry, ["rollback", "disable_readiness_gate"])

    maybe_add(
      errors,
      non_empty_string?(readiness_gate) and readiness_gate != Gates.transition_readiness_required_gate_key(),
      issue("invalid_rollback_gate", path ++ ["rollback", "disable_readiness_gate"], "Rollback readiness gate must use the external transition readiness key.")
    )
  end

  defp collect_mode_specific(errors, entry, path) do
    mode = value_at(entry, ["side_effect_mode"])

    errors
    |> collect_ready_to_land_rules(entry, mode, path)
    |> collect_shadow_rules(entry, mode, path)
  end

  defp collect_ready_to_land_rules(errors, entry, "ready_to_land_write", path) do
    gates = gate_map(entry) || %{}

    maybe_add(
      errors,
      Map.get(gates, Gates.transition_readiness_required_gate_key()) != true,
      issue(
        "transition_readiness_required",
        path ++ ["structured_plan_gates", Gates.transition_readiness_required_gate_key()],
        "Ready-to-land write claims require transition readiness enforcement."
      )
    )
  end

  defp collect_ready_to_land_rules(errors, _entry, _mode, _path), do: errors

  defp collect_shadow_rules(errors, entry, @shadow_mode, path) do
    shadow = value_at(entry, ["shadow"])

    errors
    |> collect_required_map(entry, path ++ ["shadow"])
    |> maybe_add(
      value_at(shadow, ["prefix"]) != OneShotContract.shadow_prefix(),
      issue("invalid_shadow_metadata", path ++ ["shadow", "prefix"], "Shadow metadata must use the no-production-write prefix.")
    )
    |> maybe_add(
      value_at(shadow, ["authority"]) != OneShotContract.shadow_authority(),
      issue("invalid_shadow_metadata", path ++ ["shadow", "authority"], "Shadow authority must be diagnostic-only.")
    )
    |> maybe_add(
      value_at(shadow, ["canonical_authority"]) != false,
      issue("invalid_shadow_metadata", path ++ ["shadow", "canonical_authority"], "Shadow metadata must be non-authoritative.")
    )
    |> collect_shadow_destinations(shadow, path)
    |> collect_shadow_no_write_gates(entry, path)
  end

  defp collect_shadow_rules(errors, _entry, _mode, _path), do: errors

  defp collect_shadow_destinations(errors, shadow, path) do
    destinations = value_at(shadow, ["allowed_destinations"])

    cond do
      not string_list?(destinations) or destinations == [] ->
        errors ++ [issue("required_field_missing", path ++ ["shadow", "allowed_destinations"], "Shadow destinations must be a non-empty string array.")]

      Enum.sort(destinations) != Enum.sort(OneShotContract.shadow_allowed_destinations()) ->
        errors ++
          [
            issue("invalid_shadow_metadata", path ++ ["shadow", "allowed_destinations"], "Shadow destinations must match the diagnostic-only allowlist.",
              allowed_values: OneShotContract.shadow_allowed_destinations()
            )
          ]

      true ->
        errors
    end
  end

  defp collect_shadow_no_write_gates(errors, entry, path) do
    gates = gate_map(entry) || %{}

    maybe_add(
      errors,
      Map.get(gates, Gates.transition_readiness_required_gate_key()) == true,
      issue(
        "shadow_not_authoritative",
        path ++ ["structured_plan_gates", Gates.transition_readiness_required_gate_key()],
        "Shadow/no-write entries cannot claim production transition authority."
      )
    )
  end

  defp collect_required_map(errors, map, path) do
    maybe_add(errors, not is_map(value_at(map, path_from_root(path))), issue("required_field_missing", path, "Field must be an object."))
  end

  defp collect_required_string(errors, map, path) do
    maybe_add(errors, not non_empty_string?(value_at(map, path_from_root(path))), issue("required_field_missing", path, "Field must be a non-empty string."))
  end

  defp collect_string_list(errors, map, path, message) do
    value = value_at(map, path_from_root(path))
    maybe_add(errors, not string_list?(value) or value == [], issue("required_field_missing", path, message))
  end

  defp gate_map(entry) do
    Enum.find_value(@gate_aliases, &value_at(entry, [&1]))
  end

  defp normalize_claim(claim) do
    %{
      "profile_instance_id" => value_at(claim, ["profile_instance_id"]),
      "provider_matrix" => Enum.map(value_at(claim, ["provider_matrix"]), &normalize_entry/1)
    }
  end

  defp normalize_entry(entry) do
    %{
      "id" => value_at(entry, ["id"]),
      "workflow_profile" => value_at(entry, ["workflow_profile"]),
      "tracker" => %{"kind" => value_at(entry, ["tracker", "kind"])},
      "repo_provider" => %{"kind" => value_at(entry, ["repo_provider", "kind"])},
      "agent_provider" => %{"kind" => value_at(entry, ["agent_provider", "kind"])},
      "repository_class" => value_at(entry, ["repository_class"]),
      "candidate_discovery" => value_at(entry, ["candidate_discovery"]),
      "deployment_topology" => value_at(entry, ["deployment_topology"]),
      "side_effect_mode" => value_at(entry, ["side_effect_mode"]),
      "structured_plan_gates" => gate_map(entry),
      "typed_tool_inventory" => value_at(entry, ["typed_tool_inventory"]) || value_at(entry, ["typed_tool_requirements"]),
      "evidence_files" => value_at(entry, ["evidence_files"]),
      "recovery" => value_at(entry, ["recovery"]),
      "rollback" => value_at(entry, ["rollback"]),
      "shadow" => value_at(entry, ["shadow"])
    }
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery production provider-matrix claim is invalid.",
      errors: errors
    }
  end

  defp maybe_add(errors, true, issue), do: errors ++ [issue]
  defp maybe_add(errors, false, _issue), do: errors

  defp issue(code, path, message, extra \\ []) do
    %{
      code: code,
      path: path,
      message: message
    }
    |> Map.merge(Map.new(extra))
  end

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

  defp path_from_root([_root, index | rest]) when is_integer(index), do: rest
  defp path_from_root(path), do: path

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""
  defp string_list?(values), do: is_list(values) and Enum.all?(values, &non_empty_string?/1)
end
