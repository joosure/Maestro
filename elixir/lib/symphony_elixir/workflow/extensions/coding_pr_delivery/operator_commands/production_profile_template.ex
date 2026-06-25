defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfileTemplate do
  @moduledoc """
  Operator command for Coding PR Delivery production-profile packet templates.

  The command reads one metadata JSON packet and projects the next bounded
  fill-template in the Phase 2/4 handoff. It does not read referenced evidence
  files, call providers, mutate workflow state, approve production, or enable
  gates.
  """

  @behaviour SymphonyElixir.Workflow.Extension.OperatorCommand

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.OperatorCommand
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile

  @command_id "symphony.workflow.extension.coding_pr_delivery.production_profile_template"
  @usage_error_exit_code 64
  @internal_error_exit_code 70
  @validation_failed_exit_code 1
  @schema "coding_pr_delivery.production_profile_template_result.v1"
  @switches [
    kind: :string,
    file: :string,
    provider_matrix_entry_id: :string,
    repository: :string,
    side_effect_mode: :string,
    environment: :string,
    observation_days: :integer,
    json: :boolean,
    pretty: :boolean,
    help: :boolean
  ]
  @template_kinds [
    "preflight_report_template",
    "evidence_packet_template",
    "review_packet_template",
    "enablement_request_template",
    "operator_apply_record_template",
    "observation_status_template"
  ]

  @type template_result :: {:ok, map()} | {:error, map()}

  @type deps :: %{
          required(:read_file) => (String.t() -> {:ok, binary()} | {:error, term()}),
          required(:phase2_preflight_report_template) => (map() -> template_result()),
          required(:phase2_evidence_packet_template) => (map() -> template_result()),
          required(:phase4_review_packet_template) => (map() -> template_result()),
          required(:enablement_request_template) => (map(), keyword() -> template_result()),
          required(:operator_apply_record_template) => (map() -> template_result()),
          required(:observation_status_template) => (map() -> template_result())
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
      phase2_preflight_report_template: &ProductionProfile.phase2_preflight_report_template/1,
      phase2_evidence_packet_template: &ProductionProfile.phase2_evidence_packet_template/1,
      phase4_review_packet_template: &ProductionProfile.phase4_review_packet_template/1,
      enablement_request_template: fn decision, opts -> ProductionProfile.enablement_request_template(decision, opts) end,
      operator_apply_record_template: &ProductionProfile.operator_apply_record_template/1,
      observation_status_template: &ProductionProfile.observation_status_template/1
    }
  end

  defp evaluate_argv(argv, deps) do
    case OptionParser.parse(argv, strict: @switches, aliases: [h: :help]) do
      {parsed_opts, [], []} ->
        if parsed_opts[:help] do
          {usage(), "", 0}
        else
          render_template(parsed_opts, deps)
        end

      {_opts, unexpected, []} ->
        {"", "Unexpected argument count: #{length(unexpected)}\n" <> usage(), @usage_error_exit_code}

      {_opts, _argv, invalid} ->
        {"", "Invalid option count: #{length(invalid)}\n" <> usage(), @usage_error_exit_code}
    end
  end

  defp render_template(parsed_opts, deps) do
    with {:ok, kind} <- required_kind(parsed_opts),
         {:ok, file_path} <- required_file(parsed_opts),
         {:ok, payload} <- read_json_file(file_path, deps),
         {:ok, template} <- dispatch_kind(kind, payload, parsed_opts, deps) do
      result = template_result(kind, true, "ready", template, [])
      {Jason.encode!(result, pretty: Keyword.get(parsed_opts, :pretty, false)) <> "\n", "", 0}
    else
      {:error, {:usage, message}} ->
        {"", message <> "\n" <> usage(), @usage_error_exit_code}

      {:error, {:validation, kind, reason}} ->
        result = template_result(kind, false, "invalid", nil, errors(reason))
        {Jason.encode!(result, pretty: Keyword.get(parsed_opts, :pretty, false)) <> "\n", "", @validation_failed_exit_code}
    end
  end

  defp required_kind(parsed_opts) do
    kind = parsed_opts |> Keyword.get(:kind, "") |> String.trim()

    cond do
      kind == "" ->
        {:error, {:usage, "--kind is required"}}

      kind in @template_kinds ->
        {:ok, kind}

      true ->
        {:error, {:usage, "Unsupported template kind. Expected one of: #{Enum.join(@template_kinds, ", ")}"}}
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

  defp dispatch_kind("preflight_report_template", payload, _opts, deps) do
    payload
    |> deps.phase2_preflight_report_template.()
    |> dispatch_result("preflight_report_template")
  end

  defp dispatch_kind("evidence_packet_template", payload, _opts, deps) do
    payload
    |> deps.phase2_evidence_packet_template.()
    |> dispatch_result("evidence_packet_template")
  end

  defp dispatch_kind("review_packet_template", payload, _opts, deps) do
    payload
    |> deps.phase4_review_packet_template.()
    |> dispatch_result("review_packet_template")
  end

  defp dispatch_kind("enablement_request_template", payload, opts, deps) do
    payload
    |> deps.enablement_request_template.(enablement_opts(opts))
    |> dispatch_result("enablement_request_template")
  end

  defp dispatch_kind("operator_apply_record_template", payload, _opts, deps) do
    payload
    |> deps.operator_apply_record_template.()
    |> dispatch_result("operator_apply_record_template")
  end

  defp dispatch_kind("observation_status_template", payload, _opts, deps) do
    payload
    |> deps.observation_status_template.()
    |> dispatch_result("observation_status_template")
  end

  defp dispatch_result({:ok, template}, _kind), do: {:ok, template}
  defp dispatch_result({:error, reason}, kind), do: {:error, {:validation, kind, reason}}

  defp enablement_opts(parsed_opts) do
    []
    |> maybe_put(:provider_matrix_entry_ids, Keyword.get_values(parsed_opts, :provider_matrix_entry_id))
    |> maybe_put(:repositories, Keyword.get_values(parsed_opts, :repository))
    |> maybe_put(:side_effect_mode, parsed_opts[:side_effect_mode])
    |> maybe_put(:environment, parsed_opts[:environment])
    |> maybe_put(:observation_days, parsed_opts[:observation_days])
  end

  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp template_result(kind, valid?, status, template, errors) do
    %{
      "schema" => @schema,
      "kind" => kind,
      "status" => status,
      "valid" => valid?,
      "template_schema" => template_schema(template),
      "completed_packet_schema" => completed_packet_schema(template),
      "template" => template,
      "errors" => errors,
      "does_not_collect_live_evidence" => true,
      "does_not_read_referenced_evidence_files" => true,
      "does_not_call_providers" => true,
      "does_not_mutate_workflow_state" => true,
      "does_not_approve_production" => true,
      "does_not_enable_production" => true
    }
  end

  defp template_schema(template) when is_map(template), do: Map.get(template, "schema")
  defp template_schema(_template), do: nil

  defp completed_packet_schema(template) when is_map(template), do: Map.get(template, "completed_packet_schema")
  defp completed_packet_schema(_template), do: nil

  defp errors(%{errors: errors}) when is_list(errors), do: Enum.map(errors, &error_to_map/1)
  defp errors(%{"errors" => errors}) when is_list(errors), do: Enum.map(errors, &error_to_map/1)
  defp errors(reason), do: [error_to_map(reason)]

  defp error_to_map(error) when is_map(error) do
    error
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp error_to_map(_error), do: %{"code" => "template_error", "message" => "Template generation failed."}

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
      phase2_preflight_report_template: 1,
      phase2_evidence_packet_template: 1,
      phase4_review_packet_template: 1,
      enablement_request_template: 2,
      operator_apply_record_template: 1,
      observation_status_template: 1
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
      --kind <template-kind> --file <metadata-json> [--json|--pretty]

    Template kinds:
      preflight_report_template      Input is a Phase 2 evidence plan.
      evidence_packet_template       Input is a production claim.
      review_packet_template         Input is a completed evidence packet.
      enablement_request_template    Input is a ready review decision.
      operator_apply_record_template Input is a ready operator apply plan.
      observation_status_template    Input is an accepted operator apply record.

    Enablement template options:
      --provider-matrix-entry-id <id> May be repeated.
      --repository <slug>             May be repeated.
      --side-effect-mode <mode>
      --environment <name>
      --observation-days <days>

    This command builds packet templates only. It does not collect live
    evidence, read evidence files, call providers, mutate workflow state,
    approve production, or enable gates.
    """
  end
end
