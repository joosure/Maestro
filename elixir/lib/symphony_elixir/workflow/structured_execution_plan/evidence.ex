defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Evidence do
  @moduledoc """
  Immutable evidence reference shape for structured execution plan items.

  Phase 1 stores and validates references only. Binding typed-tool results to
  evidence and recomputing item completion belongs to a later phase.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract

  @required_ref_keys ~w(evidence_id evidence_kind source producer run_id issue_id observed_at payload)
  @allowed_ref_keys @required_ref_keys ++ ["extensions"]

  @spec validate_ref(map()) :: {:ok, map()} | {:error, map()}
  def validate_ref(ref) when is_map(ref) do
    errors =
      []
      |> collect_unknown_keys(ref, @allowed_ref_keys, [])
      |> collect_required_keys(ref, @required_ref_keys, [])
      |> collect_string_field(ref, "evidence_id", [])
      |> collect_string_field(ref, "evidence_kind", [])
      |> collect_trust_class(ref, "source", [])
      |> collect_string_field(ref, "producer", [])
      |> collect_string_field(ref, "run_id", [])
      |> collect_string_field(ref, "issue_id", [])
      |> collect_timestamp_field(ref, "observed_at", [])
      |> collect_map_field(ref, "payload", [])
      |> collect_extensions(ref, [])

    if errors == [] do
      {:ok, ref}
    else
      {:error, validation_error(errors)}
    end
  end

  def validate_ref(_ref) do
    {:error,
     validation_error([
       %{code: "invalid_type", path: [], message: "Evidence reference must be an object."}
     ])}
  end

  @spec append_ref(map(), map()) :: {:ok, map()} | {:error, map()}
  def append_ref(item, evidence_ref) when is_map(item) and is_map(evidence_ref) do
    with {:ok, ref} <- validate_ref(evidence_ref),
         {:ok, refs} <- evidence_refs(item) do
      append_valid_ref(item, refs, ref)
    end
  end

  def append_ref(_item, _evidence_ref) do
    {:error,
     %{
       code: "invalid_evidence_ref",
       message: "Evidence reference append requires an item object and evidence reference object."
     }}
  end

  defp append_valid_ref(item, refs, ref) do
    case Enum.find(refs, &(Map.get(&1, "evidence_id") == Map.fetch!(ref, "evidence_id"))) do
      nil ->
        {:ok, Map.put(item, "evidence_refs", refs ++ [ref])}

      ^ref ->
        {:ok, item}

      _different_ref ->
        {:error,
         %{
           code: "evidence_ref_conflict",
           message: "Evidence references are immutable once attached.",
           evidence_id: Map.fetch!(ref, "evidence_id")
         }}
    end
  end

  defp evidence_refs(%{"evidence_refs" => refs}) when is_list(refs), do: {:ok, refs}

  defp evidence_refs(_item) do
    {:error,
     %{
       code: "invalid_evidence_refs",
       message: "Plan item evidence_refs must be an array before evidence can be appended."
     }}
  end

  defp collect_unknown_keys(errors, record, allowed_keys, path) do
    unknown_errors =
      record
      |> Map.keys()
      |> Enum.reject(&(&1 in allowed_keys))
      |> Enum.map(fn key ->
        %{code: "unknown_key", path: path ++ [key], message: "Unknown non-extension key is not allowed."}
      end)

    errors ++ unknown_errors
  end

  defp collect_required_keys(errors, record, required_keys, path) do
    required_errors =
      required_keys
      |> Enum.reject(&Map.has_key?(record, &1))
      |> Enum.map(fn key ->
        %{code: "missing_required_field", path: path ++ [key], message: "Required field is missing."}
      end)

    errors ++ required_errors
  end

  defp collect_string_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not non_empty_string?(Map.get(record, key)) do
      errors ++ [%{code: "invalid_type", path: path ++ [key], message: "Field must be a non-empty string."}]
    else
      errors
    end
  end

  defp collect_trust_class(errors, record, key, path) do
    if Map.has_key?(record, key) and not Contract.trust_class?(Map.get(record, key)) do
      errors ++ [%{code: "invalid_enum", path: path ++ [key], message: "Field must be an allowed trust class."}]
    else
      errors
    end
  end

  defp collect_timestamp_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not rfc3339?(Map.get(record, key)) do
      errors ++ [%{code: "invalid_type", path: path ++ [key], message: "Field must be an RFC 3339 timestamp."}]
    else
      errors
    end
  end

  defp collect_map_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not is_map(Map.get(record, key)) do
      errors ++ [%{code: "invalid_type", path: path ++ [key], message: "Field must be an object."}]
    else
      errors
    end
  end

  defp collect_extensions(errors, record, path) do
    case Map.fetch(record, "extensions") do
      :error ->
        errors

      {:ok, extensions} when is_map(extensions) ->
        extension_errors =
          extensions
          |> Map.keys()
          |> Enum.reject(&namespaced_key?/1)
          |> Enum.map(fn key ->
            %{
              code: "invalid_extension_key",
              path: path ++ ["extensions", key],
              message: "Extension keys must be namespaced."
            }
          end)

        errors ++ extension_errors

      {:ok, _extensions} ->
        errors ++ [%{code: "invalid_type", path: path ++ ["extensions"], message: "Extensions must be an object."}]
    end
  end

  defp validation_error(errors) do
    %{code: "schema_invalid", message: "Evidence reference failed schema validation.", errors: errors}
  end

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp rfc3339?(value) when is_binary(value) do
    match?({:ok, _datetime, _offset}, DateTime.from_iso8601(value))
  end

  defp rfc3339?(_value), do: false

  defp namespaced_key?(value) when is_binary(value), do: String.contains?(value, ".")
  defp namespaced_key?(_value), do: false
end
