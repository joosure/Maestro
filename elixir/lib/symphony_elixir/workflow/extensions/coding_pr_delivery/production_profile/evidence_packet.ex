defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidencePacket do
  @moduledoc """
  Admission checks for completed Phase 2 provider evidence packets.

  The validator proves that a packet covers the deterministic evidence runbook
  generated from a valid production claim. It validates evidence metadata only;
  it does not fetch provider state, read evidence files, or enable production
  gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.{
    Claim,
    EvidenceRunbook
  }

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract

  @schema "coding_pr_delivery.production_evidence_packet.v1"
  @error_code "coding_pr_delivery_evidence_packet_invalid"
  @shadow_mode OneShotContract.shadow_mode()
  @raw_evidence_fields [
    "stdout",
    "stderr",
    "raw_output",
    "raw_payload",
    "raw_provider_payload",
    "raw_evidence_payload",
    "response_body",
    "environment",
    "env",
    "token"
  ]
  @placeholder_tokens ["fill-", "TODO", "REPLACE", "<", ">"]

  @type validation_result :: {:ok, map()} | {:error, map()}

  @spec validate(map()) :: validation_result()
  def validate(packet) when is_map(packet) do
    claim_result = packet |> value_at(["production_claim"]) |> Claim.validate()
    runbook_result = runbook_result(claim_result)
    entries = runbook_entries(runbook_result)

    errors =
      []
      |> collect_nested_errors(claim_result, ["production_claim"])
      |> collect_scenario_evidence(packet, entries)
      |> collect_non_claim_acknowledgements(packet, entries)

    if errors == [] do
      {:ok, normalize(packet, claim_result, runbook_result)}
    else
      {:error, invalid(errors)}
    end
  end

  def validate(_packet) do
    {:error, invalid([issue("invalid_type", [], "Evidence packet must be an object.")])}
  end

  defp runbook_result({:ok, claim}), do: EvidenceRunbook.build(claim)
  defp runbook_result(_claim_result), do: {:ok, %{"entries" => []}}

  defp runbook_entries({:ok, %{"entries" => entries}}) when is_list(entries), do: entries
  defp runbook_entries(_runbook_result), do: []

  defp collect_scenario_evidence(errors, packet, entries) do
    records = value_at(packet, ["scenario_evidence"])

    cond do
      not is_list(records) or records == [] ->
        errors ++ [issue("required_field_missing", ["scenario_evidence"], "Scenario evidence must be a non-empty array.")]

      true ->
        expected_pairs = expected_scenario_pairs(entries)
        expected_set = MapSet.new(expected_pairs)
        entry_by_id = entries_by_id(entries)

        errors ++
          scenario_record_errors(records, entry_by_id, expected_set) ++
          scenario_coverage_errors(records, expected_pairs, expected_set)
    end
  end

  defp scenario_record_errors(records, entry_by_id, expected_set) do
    records
    |> Enum.with_index()
    |> Enum.flat_map(fn {record, index} -> evidence_record_errors(record, index, entry_by_id, expected_set) end)
  end

  defp evidence_record_errors(record, index, entry_by_id, expected_set) when is_map(record) do
    path = ["scenario_evidence", index]
    entry_id = value_at(record, ["provider_matrix_entry_id"])
    scenario_id = value_at(record, ["scenario_id"])
    entry = Map.get(entry_by_id, entry_id)
    pair = {entry_id, scenario_id}

    []
    |> collect_required_string(record, path ++ ["provider_matrix_entry_id"])
    |> collect_required_string(record, path ++ ["scenario_id"])
    |> maybe_add(
      non_empty_string?(entry_id) and non_empty_string?(scenario_id) and not MapSet.member?(expected_set, pair),
      issue("unknown_scenario_evidence", path, "Scenario evidence must match a provider entry and runbook scenario.", %{
        provider_matrix_entry_id: entry_id,
        scenario_id: scenario_id
      })
    )
    |> collect_required_string(record, path ++ ["collector"])
    |> collect_collected_at(record, path)
    |> collect_status(record, path)
    |> collect_evidence_files(record, path ++ ["evidence_files"])
    |> collect_raw_evidence_fields(record, path)
    |> collect_evidence_kind(record, entry, path)
    |> collect_shadow_boundary(record, entry, path)
  end

  defp evidence_record_errors(_record, index, _entry_by_id, _expected_set) do
    [issue("invalid_type", ["scenario_evidence", index], "Scenario evidence record must be an object.")]
  end

  defp collect_collected_at(errors, record, path) do
    collected_at = value_at(record, ["collected_at"])

    errors
    |> collect_required_string(record, path ++ ["collected_at"])
    |> maybe_add(
      non_empty_string?(collected_at) and not valid_datetime?(collected_at),
      issue("invalid_timestamp", path ++ ["collected_at"], "Collected-at timestamp must be ISO8601.")
    )
  end

  defp collect_status(errors, record, path) do
    status = value_at(record, ["status"])

    errors
    |> collect_required_string(record, path ++ ["status"])
    |> maybe_add(
      non_empty_string?(status) and status != "passed",
      issue("scenario_not_passed", path ++ ["status"], "Production evidence scenarios must be passed.")
    )
  end

  defp collect_evidence_files(errors, record, path) do
    evidence_files = value_at(record, [List.last(path)])

    errors =
      collect_string_list(errors, record, path, "Evidence files must be a non-empty string array.")

    if is_list(evidence_files) do
      evidence_files
      |> Enum.with_index()
      |> Enum.flat_map(fn {evidence_ref, index} -> evidence_ref_errors(evidence_ref, path ++ [index]) end)
      |> then(&(errors ++ &1))
    else
      errors
    end
  end

  defp evidence_ref_errors(evidence_ref, path) do
    []
    |> maybe_add(
      non_empty_string?(evidence_ref) and not allowed_evidence_ref?(evidence_ref),
      issue("invalid_evidence_ref", path, "Evidence references must be repository evidence paths or HTTP(S) links.")
    )
    |> maybe_add(
      non_empty_string?(evidence_ref) and placeholder_evidence_ref?(evidence_ref),
      issue("placeholder_evidence_ref", path, "Evidence references must not contain placeholders.")
    )
  end

  defp allowed_evidence_ref?(evidence_ref) do
    String.starts_with?(evidence_ref, "evidence/") or
      String.starts_with?(evidence_ref, "https://") or
      String.starts_with?(evidence_ref, "http://")
  end

  defp placeholder_evidence_ref?(evidence_ref) do
    downcased = String.downcase(evidence_ref)

    String.starts_with?(downcased, "/tmp/") or
      String.starts_with?(downcased, "tmp/") or
      String.starts_with?(downcased, "/var/") or
      String.starts_with?(downcased, "file://") or
      Enum.any?(@placeholder_tokens, &String.contains?(downcased, String.downcase(&1)))
  end

  defp collect_raw_evidence_fields(errors, record, path) do
    @raw_evidence_fields
    |> Enum.filter(&Map.has_key?(record, &1))
    |> Enum.map(fn field ->
      issue("raw_evidence_payload_forbidden", path ++ [field], "Evidence packets must not store raw provider output, environment, or token material.")
    end)
    |> then(&(errors ++ &1))
  end

  defp collect_evidence_kind(errors, record, %{"side_effect_mode" => @shadow_mode}, path) do
    evidence_kind = value_at(record, ["evidence_kind"])

    errors
    |> collect_required_string(record, path ++ ["evidence_kind"])
    |> maybe_add(
      non_empty_string?(evidence_kind) and evidence_kind != "shadow_integration",
      issue("invalid_evidence_kind", path ++ ["evidence_kind"], "Shadow provider entries must use shadow_integration evidence.")
    )
  end

  defp collect_evidence_kind(errors, record, entry, path) when is_map(entry) do
    evidence_kind = value_at(record, ["evidence_kind"])

    errors
    |> collect_required_string(record, path ++ ["evidence_kind"])
    |> maybe_add(
      non_empty_string?(evidence_kind) and evidence_kind != "real_integration",
      issue("invalid_evidence_kind", path ++ ["evidence_kind"], "Non-shadow provider entries must use real_integration evidence.")
    )
  end

  defp collect_evidence_kind(errors, _record, _entry, _path), do: errors

  defp collect_shadow_boundary(errors, record, %{"side_effect_mode" => @shadow_mode}, path) do
    shadow = value_at(record, ["shadow"])

    errors
    |> collect_required_map(record, path ++ ["shadow"])
    |> collect_required_string(shadow, path ++ ["shadow", "run_id"])
    |> maybe_add(
      value_at(shadow, ["prefix"]) != OneShotContract.shadow_prefix(),
      issue("invalid_shadow_prefix", path ++ ["shadow", "prefix"], "Shadow evidence must use the production no-write prefix.")
    )
    |> maybe_add(
      value_at(shadow, ["authority"]) != OneShotContract.shadow_authority(),
      issue("invalid_shadow_authority", path ++ ["shadow", "authority"], "Shadow evidence must use diagnostic-only authority.")
    )
    |> maybe_add(
      value_at(shadow, ["canonical_authority"]) != false,
      issue("shadow_canonical_authority", path ++ ["shadow", "canonical_authority"], "Shadow evidence must not claim canonical authority.")
    )
    |> maybe_add(
      value_at(record, ["production_write_performed"]) != false,
      issue("shadow_production_write", path ++ ["production_write_performed"], "Shadow evidence must not perform production writes.")
    )
    |> maybe_add(
      value_at(record, ["canonical_surface_mutated"]) != false,
      issue("shadow_canonical_surface_mutated", path ++ ["canonical_surface_mutated"], "Shadow evidence must not mutate canonical surfaces.")
    )
    |> collect_allowed_destinations(shadow, path ++ ["shadow", "allowed_destinations"])
  end

  defp collect_shadow_boundary(errors, _record, _entry, _path), do: errors

  defp collect_allowed_destinations(errors, shadow, path) do
    destinations = value_at(shadow, ["allowed_destinations"])
    allowed = OneShotContract.shadow_allowed_destinations()

    errors =
      collect_string_list(errors, shadow, path, "Shadow destinations must be a non-empty string array.")

    if is_list(destinations) do
      destinations
      |> Enum.reject(&(&1 in allowed))
      |> Enum.map(fn destination ->
        issue("invalid_shadow_destination", path, "Shadow evidence destination is not diagnostic-only.", %{destination: destination})
      end)
      |> then(&(errors ++ &1))
    else
      errors
    end
  end

  defp scenario_coverage_errors(records, expected_pairs, expected_set) do
    observed_pairs =
      records
      |> Enum.filter(&is_map/1)
      |> Enum.map(&{value_at(&1, ["provider_matrix_entry_id"]), value_at(&1, ["scenario_id"])})
      |> Enum.filter(fn {entry_id, scenario_id} -> non_empty_string?(entry_id) and non_empty_string?(scenario_id) end)

    observed_counts = Enum.frequencies(observed_pairs)
    observed_set = MapSet.new(observed_pairs)

    missing =
      expected_pairs
      |> Enum.reject(&MapSet.member?(observed_set, &1))
      |> Enum.map(fn {entry_id, scenario_id} ->
        issue("missing_scenario_evidence", ["scenario_evidence"], "Every runbook scenario must have one evidence record.", %{
          provider_matrix_entry_id: entry_id,
          scenario_id: scenario_id
        })
      end)

    duplicate =
      observed_counts
      |> Enum.filter(fn {_pair, count} -> count > 1 end)
      |> Enum.map(fn {{entry_id, scenario_id}, _count} ->
        issue("duplicate_scenario_evidence", ["scenario_evidence"], "A runbook scenario must not have duplicate evidence records.", %{
          provider_matrix_entry_id: entry_id,
          scenario_id: scenario_id
        })
      end)

    unknown =
      observed_pairs
      |> Enum.reject(&MapSet.member?(expected_set, &1))
      |> Enum.uniq()
      |> Enum.map(fn {entry_id, scenario_id} ->
        issue("unknown_scenario_evidence", ["scenario_evidence"], "Scenario evidence must match a runbook scenario.", %{
          provider_matrix_entry_id: entry_id,
          scenario_id: scenario_id
        })
      end)

    missing ++ duplicate ++ unknown
  end

  defp collect_non_claim_acknowledgements(errors, packet, entries) do
    acknowledgements = value_at(packet, ["non_claim_acknowledgements"])

    cond do
      not is_list(acknowledgements) or acknowledgements == [] ->
        errors ++ [issue("required_field_missing", ["non_claim_acknowledgements"], "Non-claims must be acknowledged per provider entry.")]

      true ->
        expected_non_claims = expected_non_claims_by_entry(entries)

        errors ++
          non_claim_acknowledgement_errors(acknowledgements, expected_non_claims) ++
          non_claim_acknowledgement_coverage_errors(acknowledgements, expected_non_claims)
    end
  end

  defp non_claim_acknowledgement_errors(acknowledgements, expected_non_claims) do
    acknowledgements
    |> Enum.with_index()
    |> Enum.flat_map(fn {acknowledgement, index} -> non_claim_acknowledgement_errors(acknowledgement, index, expected_non_claims) end)
  end

  defp non_claim_acknowledgement_errors(acknowledgement, index, expected_non_claims) when is_map(acknowledgement) do
    path = ["non_claim_acknowledgements", index]
    entry_id = value_at(acknowledgement, ["provider_matrix_entry_id"])
    non_claims = value_at(acknowledgement, ["non_claims"])
    expected = Map.get(expected_non_claims, entry_id, [])

    []
    |> collect_required_string(acknowledgement, path ++ ["provider_matrix_entry_id"])
    |> maybe_add(
      non_empty_string?(entry_id) and not Map.has_key?(expected_non_claims, entry_id),
      issue("unknown_provider_matrix_entry", path ++ ["provider_matrix_entry_id"], "Non-claim acknowledgement must match a provider entry.")
    )
    |> collect_required_string(acknowledgement, path ++ ["owner"])
    |> collect_acknowledged_at(acknowledgement, path)
    |> collect_string_list(acknowledgement, path ++ ["non_claims"], "Non-claims must be a non-empty string array.")
    |> collect_missing_non_claims(non_claims, expected, path)
  end

  defp non_claim_acknowledgement_errors(_acknowledgement, index, _expected_non_claims) do
    [issue("invalid_type", ["non_claim_acknowledgements", index], "Non-claim acknowledgement must be an object.")]
  end

  defp collect_acknowledged_at(errors, acknowledgement, path) do
    acknowledged_at = value_at(acknowledgement, ["acknowledged_at"])

    errors
    |> collect_required_string(acknowledgement, path ++ ["acknowledged_at"])
    |> maybe_add(
      non_empty_string?(acknowledged_at) and not valid_datetime?(acknowledged_at),
      issue("invalid_timestamp", path ++ ["acknowledged_at"], "Acknowledged-at timestamp must be ISO8601.")
    )
  end

  defp collect_missing_non_claims(errors, non_claims, expected, path) when is_list(non_claims) do
    expected
    |> Enum.reject(&(&1 in non_claims))
    |> Enum.map(fn non_claim ->
      issue("missing_non_claim_acknowledgement", path ++ ["non_claims"], "Expected non-claim is not acknowledged.", %{non_claim: non_claim})
    end)
    |> then(&(errors ++ &1))
  end

  defp collect_missing_non_claims(errors, _non_claims, _expected, _path), do: errors

  defp non_claim_acknowledgement_coverage_errors(acknowledgements, expected_non_claims) do
    observed_ids =
      acknowledgements
      |> Enum.filter(&is_map/1)
      |> Enum.map(&value_at(&1, ["provider_matrix_entry_id"]))
      |> Enum.filter(&non_empty_string?/1)

    observed_counts = Enum.frequencies(observed_ids)

    missing =
      expected_non_claims
      |> Map.keys()
      |> Enum.reject(&(&1 in observed_ids))
      |> Enum.map(fn entry_id ->
        issue("missing_non_claim_acknowledgement", ["non_claim_acknowledgements"], "Each provider entry must acknowledge explicit non-claims.", %{
          provider_matrix_entry_id: entry_id
        })
      end)

    duplicate =
      observed_counts
      |> Enum.filter(fn {_entry_id, count} -> count > 1 end)
      |> Enum.map(fn {entry_id, _count} ->
        issue("duplicate_non_claim_acknowledgement", ["non_claim_acknowledgements"], "A provider entry must not have duplicate non-claim acknowledgements.", %{
          provider_matrix_entry_id: entry_id
        })
      end)

    missing ++ duplicate
  end

  defp expected_scenario_pairs(entries) do
    Enum.flat_map(entries, fn entry ->
      entry_id = Map.get(entry, "entry_id")

      entry
      |> Map.get("scenario_checklist", [])
      |> Enum.map(&{entry_id, Map.get(&1, "id")})
      |> Enum.filter(fn {entry_id, scenario_id} -> non_empty_string?(entry_id) and non_empty_string?(scenario_id) end)
    end)
  end

  defp entries_by_id(entries) do
    entries
    |> Enum.map(&{Map.get(&1, "entry_id"), &1})
    |> Enum.filter(fn {entry_id, _entry} -> non_empty_string?(entry_id) end)
    |> Map.new()
  end

  defp expected_non_claims_by_entry(entries) do
    entries
    |> Enum.map(&{Map.get(&1, "entry_id"), Map.get(&1, "non_claims", [])})
    |> Enum.filter(fn {entry_id, non_claims} -> non_empty_string?(entry_id) and is_list(non_claims) end)
    |> Map.new()
  end

  defp normalize(packet, {:ok, claim}, {:ok, runbook}) do
    %{
      "schema" => @schema,
      "profile_instance_id" => Map.get(claim, "profile_instance_id"),
      "production_claim" => claim,
      "runbook" => runbook,
      "scenario_evidence" => value_at(packet, ["scenario_evidence"]),
      "non_claim_acknowledgements" => value_at(packet, ["non_claim_acknowledgements"])
    }
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery evidence packet is invalid.",
      errors: errors
    }
  end

  defp collect_nested_errors(errors, {:ok, _value}, _path), do: errors

  defp collect_nested_errors(errors, {:error, %{errors: nested_errors}}, path) when is_list(nested_errors) do
    errors ++ Enum.map(nested_errors, &prefix_error(&1, path))
  end

  defp prefix_error(error, path) do
    %{
      code: error_code(error),
      path: path ++ error_path(error),
      message: error_message(error)
    }
  end

  defp collect_required_string(errors, map, path) do
    maybe_add(errors, not non_empty_string?(value_at(map, local_path(path))), issue("required_field_missing", path, "Field must be a non-empty string."))
  end

  defp collect_required_map(errors, map, path) do
    maybe_add(errors, not is_map(value_at(map, local_path(path))), issue("required_field_missing", path, "Field must be an object."))
  end

  defp collect_string_list(errors, map, path, message) do
    value = value_at(map, local_path(path))

    maybe_add(errors, not string_list?(value) or value == [], issue("required_field_missing", path, message))
  end

  defp local_path(path), do: [List.last(path)]

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

  defp valid_datetime?(value) when is_binary(value) do
    match?({:ok, _datetime, _offset}, DateTime.from_iso8601(value))
  end

  defp valid_datetime?(_value), do: false

  defp string_list?(value) when is_list(value), do: Enum.all?(value, &non_empty_string?/1)
  defp string_list?(_value), do: false

  defp non_empty_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp non_empty_string?(_value), do: false

  defp error_code(error), do: Map.get(error, :code) || Map.get(error, "code") || "invalid"
  defp error_path(error), do: Map.get(error, :path) || Map.get(error, "path") || []
  defp error_message(error), do: Map.get(error, :message) || Map.get(error, "message") || "Invalid evidence packet."

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
