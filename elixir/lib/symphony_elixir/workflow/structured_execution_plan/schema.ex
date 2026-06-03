defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Schema do
  @moduledoc """
  Pure schema validation for `workflow.execution_plan.v1` canonical records.

  The validator rejects unknown top-level and item fields unless data lives
  under a namespaced `extensions` object.
  """

  alias SymphonyElixir.Workflow.RouteRef
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Evidence

  @required_plan_keys ~w(schema plan_id run_id issue_id tracker_kind workflow_profile route_key status items created_at updated_at revision)
  @allowed_plan_keys @required_plan_keys ++ ~w(issue_identifier lifecycle_phase rendering extensions)
  @required_profile_keys ~w(kind version)
  @allowed_profile_keys @required_profile_keys ++ ["extensions"]

  @required_item_keys ~w(item_id parent_item_id title kind status required criticality owned_by source depends_on evidence_requirements evidence_refs created_at updated_at revision)
  @allowed_item_keys @required_item_keys ++ ["extensions"]

  @required_evidence_requirement_keys ~w(evidence_kind required_fields trust_classes)
  @allowed_evidence_requirement_keys @required_evidence_requirement_keys ++ ["extensions"]

  @spec validate(map()) :: {:ok, map()} | {:error, map()}
  def validate(plan) when is_map(plan) do
    errors =
      []
      |> collect_unknown_keys(plan, @allowed_plan_keys, [])
      |> collect_required_keys(plan, @required_plan_keys, [])
      |> collect_schema(plan)
      |> collect_string_field(plan, "plan_id", [])
      |> collect_string_field(plan, "run_id", [])
      |> collect_string_field(plan, "issue_id", [])
      |> collect_optional_string_field(plan, "issue_identifier", [])
      |> collect_string_field(plan, "tracker_kind", [])
      |> collect_profile(plan)
      |> collect_string_field(plan, "route_key", [])
      |> collect_route_ref(plan)
      |> collect_optional_string_field(plan, "lifecycle_phase", [])
      |> collect_enum_field(plan, "status", &Contract.plan_status?/1, [])
      |> collect_items(plan)
      |> collect_optional_map_field(plan, "rendering", [])
      |> collect_timestamp_field(plan, "created_at", [])
      |> collect_timestamp_field(plan, "updated_at", [])
      |> collect_positive_integer_field(plan, "revision", [])
      |> collect_extensions(plan, [])

    if errors == [] do
      {:ok, plan}
    else
      {:error, validation_error(errors)}
    end
  end

  def validate(_plan) do
    {:error,
     validation_error([
       %{code: "invalid_type", path: [], message: "Plan record must be an object."}
     ])}
  end

  defp collect_schema(errors, %{"schema" => schema}) do
    if schema == Contract.schema_id() do
      errors
    else
      errors ++ [%{code: "invalid_schema", path: ["schema"], message: "Unsupported structured plan schema."}]
    end
  end

  defp collect_schema(errors, plan) do
    if Map.has_key?(plan, "schema") do
      errors ++ [%{code: "invalid_schema", path: ["schema"], message: "Unsupported structured plan schema."}]
    else
      errors
    end
  end

  defp collect_profile(errors, %{"workflow_profile" => profile}) when is_map(profile) do
    errors
    |> collect_unknown_keys(profile, @allowed_profile_keys, ["workflow_profile"])
    |> collect_required_keys(profile, @required_profile_keys, ["workflow_profile"])
    |> collect_string_field(profile, "kind", ["workflow_profile"])
    |> collect_positive_integer_field(profile, "version", ["workflow_profile"])
    |> collect_extensions(profile, ["workflow_profile"])
  end

  defp collect_profile(errors, plan) do
    if Map.has_key?(plan, "workflow_profile") do
      errors ++
        [
          %{
            code: "invalid_type",
            path: ["workflow_profile"],
            message: "Workflow profile must be an object."
          }
        ]
    else
      errors
    end
  end

  defp collect_route_ref(errors, %{"workflow_profile" => workflow_profile, "route_key" => route_key})
       when is_map(workflow_profile) and is_binary(route_key) do
    case RouteRef.new(workflow_profile, route_key) do
      {:ok, _route_ref} ->
        errors

      {:error, reason} ->
        errors ++
          [
            %{
              code: "invalid_route_ref",
              path: ["route_key"],
              message: "Route key is not supported by the workflow profile.",
              reason: inspect(reason)
            }
          ]
    end
  end

  defp collect_route_ref(errors, _plan), do: errors

  defp collect_items(errors, %{"items" => items}) when is_list(items) do
    item_errors =
      items
      |> Enum.with_index()
      |> Enum.flat_map(fn {item, index} -> validate_item_errors(item, index) end)

    errors ++ item_errors ++ duplicate_item_id_errors(items)
  end

  defp collect_items(errors, plan) do
    if Map.has_key?(plan, "items") do
      errors ++ [%{code: "invalid_type", path: ["items"], message: "Items must be an array."}]
    else
      errors
    end
  end

  defp validate_item_errors(item, index) when is_map(item) do
    path = ["items", index]

    []
    |> collect_unknown_keys(item, @allowed_item_keys, path)
    |> collect_required_keys(item, @required_item_keys, path)
    |> collect_string_field(item, "item_id", path)
    |> collect_nullable_string_field(item, "parent_item_id", path)
    |> collect_string_field(item, "title", path)
    |> collect_enum_field(item, "kind", &Contract.item_kind?/1, path)
    |> collect_enum_field(item, "status", &Contract.item_status?/1, path)
    |> collect_boolean_field(item, "required", path)
    |> collect_enum_field(item, "criticality", &Contract.criticality?/1, path)
    |> collect_enum_field(item, "owned_by", &Contract.owner?/1, path)
    |> collect_enum_field(item, "source", &Contract.source?/1, path)
    |> collect_string_list_field(item, "depends_on", path)
    |> collect_evidence_requirements(item, path)
    |> collect_evidence_refs(item, path)
    |> collect_timestamp_field(item, "created_at", path)
    |> collect_timestamp_field(item, "updated_at", path)
    |> collect_positive_integer_field(item, "revision", path)
    |> collect_extensions(item, path)
  end

  defp validate_item_errors(_item, index) do
    [%{code: "invalid_type", path: ["items", index], message: "Plan item must be an object."}]
  end

  defp duplicate_item_id_errors(items) do
    item_ids =
      items
      |> Enum.filter(&is_map/1)
      |> Enum.map(&Map.get(&1, "item_id"))
      |> Enum.filter(&non_empty_string?/1)

    item_ids
    |> Enum.frequencies()
    |> Enum.filter(fn {_item_id, count} -> count > 1 end)
    |> Enum.map(fn {item_id, _count} ->
      %{code: "duplicate_item_id", path: ["items"], message: "Plan item ids must be unique.", item_id: item_id}
    end)
  end

  defp collect_evidence_requirements(errors, item, path) do
    case Map.fetch(item, "evidence_requirements") do
      {:ok, requirements} when is_list(requirements) ->
        evidence_requirement_errors =
          requirements
          |> Enum.with_index()
          |> Enum.flat_map(fn {requirement, index} ->
            validate_evidence_requirement_errors(requirement, path ++ ["evidence_requirements", index])
          end)

        errors ++ evidence_requirement_errors ++ critical_evidence_requirement_errors(item, path)

      {:ok, _requirements} ->
        errors ++
          [
            %{
              code: "invalid_type",
              path: path ++ ["evidence_requirements"],
              message: "Evidence requirements must be an array."
            }
          ]

      :error ->
        errors
    end
  end

  defp validate_evidence_requirement_errors(requirement, path) when is_map(requirement) do
    []
    |> collect_unknown_keys(requirement, @allowed_evidence_requirement_keys, path)
    |> collect_required_keys(requirement, @required_evidence_requirement_keys, path)
    |> collect_string_field(requirement, "evidence_kind", path)
    |> collect_string_list_field(requirement, "required_fields", path)
    |> collect_trust_class_list_field(requirement, "trust_classes", path)
    |> collect_extensions(requirement, path)
  end

  defp validate_evidence_requirement_errors(_requirement, path) do
    [%{code: "invalid_type", path: path, message: "Evidence requirement must be an object."}]
  end

  defp critical_evidence_requirement_errors(%{"criticality" => criticality, "evidence_requirements" => []}, path)
       when criticality in ["handoff_blocking", "profile_required"] do
    [
      %{
        code: "missing_evidence_requirements",
        path: path ++ ["evidence_requirements"],
        message: "Critical plan items must declare evidence requirements."
      }
    ]
  end

  defp critical_evidence_requirement_errors(_item, _path), do: []

  defp collect_evidence_refs(errors, item, path) do
    case Map.fetch(item, "evidence_refs") do
      {:ok, refs} when is_list(refs) ->
        ref_errors =
          refs
          |> Enum.with_index()
          |> Enum.flat_map(fn {ref, index} ->
            case Evidence.validate_ref(ref) do
              {:ok, _ref} ->
                []

              {:error, %{errors: errors}} ->
                Enum.map(errors, fn error -> Map.update!(error, :path, &(path ++ ["evidence_refs", index] ++ &1)) end)
            end
          end)

        errors ++ ref_errors ++ duplicate_evidence_ref_errors(refs, path)

      {:ok, _refs} ->
        errors ++ [%{code: "invalid_type", path: path ++ ["evidence_refs"], message: "Evidence refs must be an array."}]

      :error ->
        errors
    end
  end

  defp duplicate_evidence_ref_errors(refs, path) do
    refs
    |> Enum.filter(&is_map/1)
    |> Enum.map(&Map.get(&1, "evidence_id"))
    |> Enum.filter(&non_empty_string?/1)
    |> Enum.frequencies()
    |> Enum.filter(fn {_evidence_id, count} -> count > 1 end)
    |> Enum.map(fn {evidence_id, _count} ->
      %{
        code: "duplicate_evidence_ref",
        path: path ++ ["evidence_refs"],
        message: "Evidence refs must not contain duplicate evidence ids.",
        evidence_id: evidence_id
      }
    end)
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

  defp collect_optional_string_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not non_empty_string?(Map.get(record, key)) do
      errors ++ [%{code: "invalid_type", path: path ++ [key], message: "Optional field must be a non-empty string."}]
    else
      errors
    end
  end

  defp collect_nullable_string_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not nullable_non_empty_string?(Map.get(record, key)) do
      errors ++ [%{code: "invalid_type", path: path ++ [key], message: "Field must be a non-empty string or null."}]
    else
      errors
    end
  end

  defp collect_enum_field(errors, record, key, predicate, path) do
    if Map.has_key?(record, key) and not predicate.(Map.get(record, key)) do
      errors ++ [%{code: "invalid_enum", path: path ++ [key], message: "Field contains an unsupported enum value."}]
    else
      errors
    end
  end

  defp collect_boolean_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not is_boolean(Map.get(record, key)) do
      errors ++ [%{code: "invalid_type", path: path ++ [key], message: "Field must be a boolean."}]
    else
      errors
    end
  end

  defp collect_string_list_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not string_list?(Map.get(record, key)) do
      errors ++ [%{code: "invalid_type", path: path ++ [key], message: "Field must be an array of strings."}]
    else
      errors
    end
  end

  defp collect_trust_class_list_field(errors, record, key, path) do
    case Map.fetch(record, key) do
      {:ok, values} when is_list(values) ->
        invalid_values = Enum.reject(values, &Contract.trust_class?/1)

        if invalid_values == [] do
          errors
        else
          errors ++
            [
              %{
                code: "invalid_enum",
                path: path ++ [key],
                message: "Trust classes must be allowed structured execution plan trust classes.",
                invalid_values: invalid_values
              }
            ]
        end

      {:ok, _values} ->
        errors ++ [%{code: "invalid_type", path: path ++ [key], message: "Field must be an array of trust classes."}]

      :error ->
        errors
    end
  end

  defp collect_optional_map_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not is_map(Map.get(record, key)) do
      errors ++ [%{code: "invalid_type", path: path ++ [key], message: "Optional field must be an object."}]
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

  defp collect_positive_integer_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not positive_integer?(Map.get(record, key)) do
      errors ++ [%{code: "invalid_type", path: path ++ [key], message: "Field must be a positive integer."}]
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
    %{code: "schema_invalid", message: "Structured execution plan failed schema validation.", errors: errors}
  end

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp nullable_non_empty_string?(nil), do: true
  defp nullable_non_empty_string?(value), do: non_empty_string?(value)

  defp string_list?(values) when is_list(values), do: Enum.all?(values, &non_empty_string?/1)
  defp string_list?(_values), do: false

  defp rfc3339?(value) when is_binary(value) do
    match?({:ok, _datetime, _offset}, DateTime.from_iso8601(value))
  end

  defp rfc3339?(_value), do: false

  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp namespaced_key?(value) when is_binary(value), do: String.contains?(value, ".")
  defp namespaced_key?(_value), do: false
end
