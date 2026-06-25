defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfileValidate do
  @moduledoc """
  Operator command for Coding PR Delivery production-profile packet validation.

  The command reads one metadata JSON packet, validates or projects it through
  the production-profile facade, and emits a bounded JSON result. It does not
  read referenced evidence files, call providers, mutate workflow state, approve
  production, or enable gates.
  """

  @behaviour SymphonyElixir.Workflow.Extension.OperatorCommand

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.OperatorCommand
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile

  @command_id "symphony.workflow.extension.coding_pr_delivery.production_profile_validate"
  @usage_error_exit_code 64
  @internal_error_exit_code 70
  @validation_failed_exit_code 1
  @schema "coding_pr_delivery.production_profile_validation_result.v1"
  @switches [
    kind: :string,
    file: :string,
    json: :boolean,
    pretty: :boolean,
    help: :boolean
  ]
  @validation_kinds [
    "provider_matrix",
    "provider_matrix_entry",
    "typed_tool_exception",
    "claim",
    "evidence_packet",
    "review_packet",
    "enablement_request",
    "operator_apply_record",
    "observation_status"
  ]
  @projection_kinds ["review_decision", "observation_decision"]
  @kinds @validation_kinds ++ @projection_kinds

  @type validation_result :: {:ok, map()} | {:error, map()}

  @type deps :: %{
          required(:read_file) => (String.t() -> {:ok, binary()} | {:error, term()}),
          required(:validate_provider_matrix) => (map() -> validation_result()),
          required(:validate_provider_matrix_entry) => (map() -> validation_result()),
          required(:validate_typed_tool_exception) => (map() -> validation_result()),
          required(:validate_claim) => (map() -> validation_result()),
          required(:validate_evidence_packet) => (map() -> validation_result()),
          required(:validate_review_packet) => (map() -> validation_result()),
          required(:review_decision) => (map() -> {:ok, map()}),
          required(:validate_enablement_request) => (map() -> validation_result()),
          required(:validate_operator_apply_record) => (map() -> validation_result()),
          required(:validate_observation_status) => (map() -> validation_result()),
          required(:observation_decision) => (map() -> {:ok, map()})
        }

  @impl true
  def id, do: @command_id

  @impl true
  @spec evaluate([String.t()], keyword()) :: OperatorCommand.result()
  def evaluate(argv, command_opts \\ []) do
    with :ok <- validate_argv(argv),
         {:ok, deps} <- command_deps(command_opts) do
      evaluate_argv(argv, deps)
    else
      {:error, {:usage_error, reason}} ->
        {"", format_usage_error(reason) <> "\n" <> usage(), @usage_error_exit_code}

      {:error, {:internal_error, reason}} ->
        {"", format_internal_error(reason), @internal_error_exit_code}
    end
  end

  @spec runtime_deps() :: deps()
  def runtime_deps do
    %{
      read_file: &File.read/1,
      validate_provider_matrix: &ProductionProfile.validate_provider_matrix/1,
      validate_provider_matrix_entry: &ProductionProfile.validate_provider_matrix_entry/1,
      validate_typed_tool_exception: &ProductionProfile.validate_typed_tool_exception/1,
      validate_claim: &ProductionProfile.validate_claim/1,
      validate_evidence_packet: &ProductionProfile.validate_evidence_packet/1,
      validate_review_packet: &ProductionProfile.validate_review_packet/1,
      review_decision: &ProductionProfile.review_decision/1,
      validate_enablement_request: &ProductionProfile.validate_enablement_request/1,
      validate_operator_apply_record: &ProductionProfile.validate_operator_apply_record/1,
      validate_observation_status: &ProductionProfile.validate_observation_status/1,
      observation_decision: &ProductionProfile.observation_decision/1
    }
  end

  defp evaluate_argv(argv, deps) do
    case OptionParser.parse(argv, strict: @switches, aliases: [h: :help]) do
      {parsed_opts, [], []} ->
        if parsed_opts[:help] do
          {usage(), "", 0}
        else
          validate_packet(parsed_opts, deps)
        end

      {_opts, unexpected, []} ->
        {"", "Unexpected argument count: #{length(unexpected)}\n" <> usage(), @usage_error_exit_code}

      {_opts, _argv, invalid} ->
        {"", "Invalid option count: #{length(invalid)}\n" <> usage(), @usage_error_exit_code}
    end
  end

  defp validate_packet(parsed_opts, deps) do
    with {:ok, kind} <- required_kind(parsed_opts),
         {:ok, file_path} <- required_file(parsed_opts),
         {:ok, payload} <- read_json_file(file_path, deps),
         {:ok, result, exit_code} <- dispatch_kind(kind, payload, deps) do
      {Jason.encode!(result, pretty: Keyword.get(parsed_opts, :pretty, false)) <> "\n", "", exit_code}
    else
      {:error, {:usage, message}} ->
        {"", message <> "\n" <> usage(), @usage_error_exit_code}

      {:error, {:validation, result}} ->
        {Jason.encode!(result, pretty: Keyword.get(parsed_opts, :pretty, false)) <> "\n", "", @validation_failed_exit_code}
    end
  end

  defp required_kind(parsed_opts) do
    kind = parsed_opts |> Keyword.get(:kind, "") |> String.trim()

    cond do
      kind == "" ->
        {:error, {:usage, "--kind is required"}}

      kind in @kinds ->
        {:ok, kind}

      true ->
        {:error, {:usage, "Unsupported packet kind. Expected one of: #{Enum.join(@kinds, ", ")}"}}
    end
  end

  defp required_file(parsed_opts) do
    file = parsed_opts |> Keyword.get(:file, "") |> String.trim()

    if file == "" do
      {:error, {:usage, "--file is required"}}
    else
      {:ok, file}
    end
  end

  defp read_json_file(file_path, deps) do
    with {:ok, contents} <- deps.read_file.(file_path),
         {:ok, decoded} <- Jason.decode(contents),
         true <- is_map(decoded) do
      {:ok, decoded}
    else
      {:error, _reason} ->
        {:error, {:usage, "Unable to read or parse metadata JSON file."}}

      false ->
        {:error, {:usage, "Metadata JSON file must contain an object."}}
    end
  end

  defp dispatch_kind(kind, payload, deps) when kind in @validation_kinds do
    kind
    |> validate_kind(payload, deps)
    |> case do
      {:ok, normalized} ->
        {:ok, validation_result(kind, true, "valid", summary(kind, normalized), []), 0}

      {:error, reason} ->
        {:error, {:validation, validation_result(kind, false, "invalid", %{}, errors(reason))}}
    end
  end

  defp dispatch_kind("review_decision" = kind, payload, deps) do
    {:ok, decision} = deps.review_decision.(payload)
    {:ok, projection_result(kind, decision, Map.get(decision, "status")), 0}
  end

  defp dispatch_kind("observation_decision" = kind, payload, deps) do
    {:ok, decision} = deps.observation_decision.(payload)
    {:ok, projection_result(kind, decision, Map.get(decision, "status")), 0}
  end

  defp validate_kind("provider_matrix", payload, deps), do: deps.validate_provider_matrix.(payload)
  defp validate_kind("provider_matrix_entry", payload, deps), do: deps.validate_provider_matrix_entry.(payload)
  defp validate_kind("typed_tool_exception", payload, deps), do: deps.validate_typed_tool_exception.(payload)
  defp validate_kind("claim", payload, deps), do: deps.validate_claim.(payload)
  defp validate_kind("evidence_packet", payload, deps), do: deps.validate_evidence_packet.(payload)
  defp validate_kind("review_packet", payload, deps), do: deps.validate_review_packet.(payload)
  defp validate_kind("enablement_request", payload, deps), do: deps.validate_enablement_request.(payload)
  defp validate_kind("operator_apply_record", payload, deps), do: deps.validate_operator_apply_record.(payload)
  defp validate_kind("observation_status", payload, deps), do: deps.validate_observation_status.(payload)

  defp validation_result(kind, valid?, status, summary, errors) do
    %{
      "schema" => @schema,
      "kind" => kind,
      "status" => status,
      "valid" => valid?,
      "summary" => summary,
      "errors" => errors,
      "normalized_packet_included" => false,
      "raw_input_included" => false,
      "does_not_read_referenced_evidence_files" => true,
      "does_not_call_providers" => true,
      "does_not_mutate_workflow_state" => true,
      "does_not_approve_production" => true,
      "does_not_enable_production" => true
    }
  end

  defp projection_result(kind, projection, status) do
    %{
      "schema" => @schema,
      "kind" => kind,
      "status" => status,
      "valid" => status in ["ready_for_approval", "passed"],
      "projection" => projection,
      "errors" => [],
      "normalized_packet_included" => false,
      "raw_input_included" => false,
      "does_not_read_referenced_evidence_files" => true,
      "does_not_call_providers" => true,
      "does_not_mutate_workflow_state" => true,
      "does_not_approve_production" => true,
      "does_not_enable_production" => true
    }
  end

  defp summary("claim", packet) do
    provider_matrix = Map.get(packet, "provider_matrix", [])

    %{
      "profile_instance_id" => Map.get(packet, "profile_instance_id"),
      "provider_matrix_entry_count" => length(provider_matrix),
      "provider_matrix_entry_ids" => ids(provider_matrix),
      "side_effect_modes" => unique_values(provider_matrix, "side_effect_mode")
    }
  end

  defp summary("evidence_packet", packet) do
    %{
      "profile_instance_id" => Map.get(packet, "profile_instance_id"),
      "scenario_evidence_count" => count(packet, "scenario_evidence"),
      "non_claim_acknowledgement_count" => count(packet, "non_claim_acknowledgements"),
      "provider_matrix_entry_ids" => ids(get_in(packet, ["runbook", "entries"]) || [])
    }
  end

  defp summary("review_packet", packet) do
    %{
      "review_packet_id" => Map.get(packet, "review_packet_id"),
      "profile_instance_id" => Map.get(packet, "profile_instance_id"),
      "owner_signoff_count" => count(packet, "owner_signoffs"),
      "deterministic_test_count" => count(packet, "deterministic_test_matrix")
    }
  end

  defp summary("enablement_request", packet) do
    %{
      "enablement_request_id" => Map.get(packet, "enablement_request_id"),
      "environment" => value_at(packet, ["scope", "environment"]),
      "side_effect_mode" => value_at(packet, ["scope", "side_effect_mode"]),
      "provider_matrix_entry_ids" => value_at(packet, ["scope", "provider_matrix_entry_ids"]) || []
    }
  end

  defp summary("operator_apply_record", packet) do
    %{
      "apply_record_id" => Map.get(packet, "apply_record_id"),
      "applied_by" => value_at(packet, ["apply_metadata", "applied_by"]),
      "operator_confirmation" => value_at(packet, ["apply_metadata", "operator_confirmation"])
    }
  end

  defp summary("observation_status", packet) do
    %{
      "observation_status_id" => Map.get(packet, "observation_status_id"),
      "status" => Map.get(packet, "status"),
      "criteria_result_count" => count(packet, "criteria_results")
    }
  end

  defp summary(_kind, packet) do
    %{
      "profile_instance_id" => Map.get(packet, "profile_instance_id"),
      "provider_matrix_entry_ids" => ids(Map.get(packet, "provider_matrix", []))
    }
  end

  defp ids(entries) when is_list(entries) do
    entries
    |> Enum.map(&Map.get(&1, "id", Map.get(&1, "entry_id")))
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp ids(_entries), do: []

  defp unique_values(entries, field) when is_list(entries) do
    entries
    |> Enum.map(&Map.get(&1, field))
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp count(packet, field) do
    case Map.get(packet, field) do
      values when is_list(values) -> length(values)
      _missing -> 0
    end
  end

  defp errors(%{errors: errors}) when is_list(errors), do: Enum.map(errors, &error_to_map/1)
  defp errors(%{"errors" => errors}) when is_list(errors), do: Enum.map(errors, &error_to_map/1)
  defp errors(reason), do: [error_to_map(reason)]

  defp error_to_map(error) when is_map(error) do
    error
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp error_to_map(_error), do: %{"code" => "validation_error", "message" => "Packet validation failed."}

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

  defp validate_argv(argv) when is_list(argv) do
    if Enum.all?(argv, &is_binary/1) do
      :ok
    else
      {:error, {:usage_error, {:argv_contains_non_string, first_invalid_type(argv)}}}
    end
  end

  defp validate_argv(argv), do: {:error, {:usage_error, {:argv_not_list, Diagnostics.type_name(argv)}}}

  defp command_deps(command_opts) when is_list(command_opts) do
    with true <- Keyword.keyword?(command_opts),
         deps <- Keyword.get(command_opts, :deps, runtime_deps()),
         :ok <- validate_deps(deps) do
      {:ok, deps}
    else
      false ->
        {:error, {:internal_error, {:command_opts_not_keyword, Diagnostics.type_name(command_opts)}}}

      {:error, reason} ->
        {:error, {:internal_error, reason}}
    end
  end

  defp command_deps(command_opts),
    do: {:error, {:internal_error, {:command_opts_not_keyword, Diagnostics.type_name(command_opts)}}}

  defp validate_deps(deps) when is_map(deps) do
    required_deps()
    |> Enum.find(fn {key, arity} -> not is_function(Map.get(deps, key), arity) end)
    |> case do
      nil -> :ok
      {key, _arity} -> {:error, {:dependency_invalid, key, Diagnostics.type_name(Map.get(deps, key))}}
    end
  end

  defp validate_deps(deps), do: {:error, {:deps_invalid, Diagnostics.type_name(deps)}}

  defp required_deps do
    [
      read_file: 1,
      validate_provider_matrix: 1,
      validate_provider_matrix_entry: 1,
      validate_typed_tool_exception: 1,
      validate_claim: 1,
      validate_evidence_packet: 1,
      validate_review_packet: 1,
      review_decision: 1,
      validate_enablement_request: 1,
      validate_operator_apply_record: 1,
      validate_observation_status: 1,
      observation_decision: 1
    ]
  end

  defp first_invalid_type(argv) do
    argv
    |> Enum.find(&(not is_binary(&1)))
    |> Diagnostics.type_name()
  end

  defp format_usage_error({:argv_not_list, type}), do: "Command argv must be a list of strings: value_type=#{type}"
  defp format_usage_error({:argv_contains_non_string, type}), do: "Command argv must contain only strings: value_type=#{type}"

  defp format_internal_error({:command_opts_not_keyword, type}),
    do: "Coding PR Delivery operator command options are invalid: reason=command_opts_not_keyword value_type=#{type}\n"

  defp format_internal_error({:dependency_invalid, key, type}),
    do: "Coding PR Delivery operator command options are invalid: reason=dependency_invalid dependency=#{key} value_type=#{type}\n"

  defp format_internal_error({:deps_invalid, type}),
    do: "Coding PR Delivery operator command options are invalid: reason=deps_invalid value_type=#{type}\n"

  defp usage do
    """
    Command arguments:
      --kind <packet-kind> --file <metadata-json> [--json|--pretty]

    Validation kinds:
      provider_matrix
      provider_matrix_entry
      typed_tool_exception
      claim
      evidence_packet
      review_packet
      enablement_request
      operator_apply_record
      observation_status

    Projection kinds:
      review_decision        Input is a review packet.
      observation_decision   Input is an observation status packet.

    This command validates metadata packets only. It does not read referenced
    evidence files, call providers, mutate workflow state, approve production,
    or enable gates.
    """
  end
end
