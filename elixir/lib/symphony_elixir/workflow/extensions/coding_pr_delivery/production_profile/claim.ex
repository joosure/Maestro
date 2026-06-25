defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Claim do
  @moduledoc """
  Admission checks for complete Coding PR Delivery production claims.

  This validator composes provider-matrix, structured-plan governance, and
  optional typed-tool exception evidence into one review-packet boundary. It is
  pure and does not enable providers, gates, or workflow side effects.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ProviderMatrix
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.TypedToolException
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProductionProfile.Governance

  @error_code "coding_pr_delivery_production_claim_invalid"

  @type validation_result :: {:ok, map()} | {:error, map()}

  @spec validate(map()) :: validation_result()
  def validate(claim) when is_map(claim) do
    profile_instance_id = value_at(claim, ["profile_instance_id"])
    provider_matrix_result = ProviderMatrix.validate_claim(claim)
    provider_entries = normalized_provider_entries(provider_matrix_result)

    errors =
      []
      |> collect_required_string(claim, ["profile_instance_id"])
      |> collect_nested_errors(provider_matrix_result, [])
      |> collect_governance_packets(claim, profile_instance_id, provider_entries)
      |> collect_typed_tool_exceptions(claim, provider_entries)

    if errors == [] do
      {:ok, normalize_claim(claim, provider_matrix_result)}
    else
      {:error, invalid(errors)}
    end
  end

  def validate(_claim) do
    {:error, invalid([issue("invalid_type", [], "Production claim must be an object.")])}
  end

  defp collect_governance_packets(errors, claim, profile_instance_id, provider_entries) do
    packets = value_at(claim, ["production_governance"])

    cond do
      not is_list(packets) or packets == [] ->
        errors ++ [issue("required_field_missing", ["production_governance"], "Production governance packets must be a non-empty array.")]

      true ->
        governance_errors =
          packets
          |> Enum.with_index()
          |> Enum.flat_map(fn {packet, index} -> governance_packet_errors(packet, index, profile_instance_id, provider_entries) end)

        errors ++ governance_errors ++ governance_coverage_errors(packets, provider_entries)
    end
  end

  defp governance_packet_errors(packet, index, profile_instance_id, provider_entries) when is_map(packet) do
    path = ["production_governance", index]
    entry_id = value_at(packet, ["provider_matrix_entry_id"])
    normalized_entry_ids = Enum.map(provider_entries, &Map.get(&1, "id"))

    []
    |> maybe_add(
      not non_empty_string?(entry_id),
      issue("required_field_missing", path ++ ["provider_matrix_entry_id"], "Governance packet must name its provider-matrix entry.")
    )
    |> maybe_add(
      non_empty_string?(entry_id) and entry_id not in normalized_entry_ids,
      issue("unknown_provider_matrix_entry", path ++ ["provider_matrix_entry_id"], "Governance packet references a provider-matrix entry outside this claim.")
    )
    |> maybe_add(
      non_empty_string?(profile_instance_id) and value_at(packet, ["profile_instance_id"]) != profile_instance_id,
      issue("profile_instance_mismatch", path ++ ["profile_instance_id"], "Governance packet profile instance must match the production claim.")
    )
    |> collect_nested_errors(Governance.validate_packet(packet), path)
  end

  defp governance_packet_errors(_packet, index, _profile_instance_id, _provider_entries) do
    [issue("invalid_type", ["production_governance", index], "Production governance packet must be an object.")]
  end

  defp governance_coverage_errors(packets, provider_entries) do
    entry_ids = provider_entries |> Enum.map(&Map.get(&1, "id")) |> Enum.reject(&is_nil/1)
    governance_ids = packets |> Enum.filter(&is_map/1) |> Enum.map(&value_at(&1, ["provider_matrix_entry_id"])) |> Enum.reject(&is_nil/1)
    governance_id_counts = Enum.frequencies(governance_ids)

    missing =
      entry_ids
      |> Enum.reject(&(&1 in governance_ids))
      |> Enum.map(fn _entry_id ->
        issue("missing_governance_packet", ["production_governance"], "Each provider-matrix entry must have one production governance packet.")
      end)

    duplicate =
      governance_id_counts
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> Enum.map(fn {_id, _count} ->
        issue("duplicate_governance_packet", ["production_governance"], "A provider-matrix entry must not have duplicate governance packets.")
      end)

    missing ++ duplicate
  end

  defp collect_typed_tool_exceptions(errors, claim, provider_entries) do
    exceptions = value_at(claim, ["typed_tool_exceptions"])

    cond do
      is_nil(exceptions) ->
        errors

      not is_list(exceptions) ->
        errors ++ [issue("invalid_type", ["typed_tool_exceptions"], "Typed-tool exceptions must be an array when present.")]

      true ->
        exception_errors =
          exceptions
          |> Enum.with_index()
          |> Enum.flat_map(fn {exception, index} -> typed_tool_exception_errors(exception, index, provider_entries) end)

        errors ++ exception_errors
    end
  end

  defp typed_tool_exception_errors(exception, index, provider_entries) when is_map(exception) do
    path = ["typed_tool_exceptions", index]
    result = TypedToolException.validate_record(exception)

    []
    |> collect_nested_errors(result, path)
    |> maybe_add(
      match?({:ok, _}, result) and not Enum.any?(provider_entries, &exception_matches_entry?(exception, &1)),
      issue("exception_provider_scope_unmatched", path, "Typed-tool exception must match a provider-matrix entry in this claim.")
    )
  end

  defp typed_tool_exception_errors(_exception, index, _provider_entries) do
    [issue("invalid_type", ["typed_tool_exceptions", index], "Typed-tool exception must be an object.")]
  end

  defp exception_matches_entry?(exception, entry) when is_map(exception) and is_map(entry) do
    value_at(exception, ["workflow_profile"]) == Map.get(entry, "workflow_profile") and
      value_at(exception, ["tracker", "kind"]) == value_at(entry, ["tracker", "kind"]) and
      value_at(exception, ["repo_provider", "kind"]) == value_at(entry, ["repo_provider", "kind"]) and
      value_at(exception, ["agent_provider", "kind"]) == value_at(entry, ["agent_provider", "kind"]) and
      value_at(exception, ["repository_class"]) == Map.get(entry, "repository_class")
  end

  defp exception_matches_entry?(_exception, _entry), do: false

  defp collect_nested_errors(errors, {:ok, _value}, _path), do: errors

  defp collect_nested_errors(errors, {:error, %{errors: nested_errors}}, path) when is_list(nested_errors) do
    errors ++ Enum.map(nested_errors, &prefix_error(&1, path))
  end

  defp collect_nested_errors(errors, {:error, reason}, path) do
    errors ++ [issue(error_code(reason), path, error_message(reason))]
  end

  defp normalized_provider_entries({:ok, %{"provider_matrix" => entries}}) when is_list(entries), do: entries
  defp normalized_provider_entries(_result), do: []

  defp normalize_claim(claim, {:ok, provider_matrix}) do
    %{
      "profile_instance_id" => value_at(claim, ["profile_instance_id"]),
      "provider_matrix" => Map.get(provider_matrix, "provider_matrix"),
      "production_governance" => value_at(claim, ["production_governance"]),
      "typed_tool_exceptions" => value_at(claim, ["typed_tool_exceptions"]) || []
    }
  end

  defp collect_required_string(errors, map, path) do
    maybe_add(errors, not non_empty_string?(value_at(map, path)), issue("required_field_missing", path, "Field must be a non-empty string."))
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery production claim is invalid.",
      errors: errors
    }
  end

  defp prefix_error(error, path) do
    %{
      code: error_code(error),
      path: path ++ error_path(error),
      message: error_message(error)
    }
  end

  defp error_code(error), do: Map.get(error, :code) || Map.get(error, "code") || "invalid"
  defp error_path(error), do: Map.get(error, :path) || Map.get(error, "path") || []
  defp error_message(error), do: Map.get(error, :message) || Map.get(error, "message") || "Invalid production claim."

  defp maybe_add(errors, true, issue), do: errors ++ [issue]
  defp maybe_add(errors, false, _issue), do: errors

  defp issue(code, path, message) do
    %{
      code: code,
      path: path,
      message: message
    }
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

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""
end
