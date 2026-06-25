defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfilePreflightCollect do
  @moduledoc """
  Operator command for Phase 2 read-only provider preflight collection.

  The command builds a Coding PR Delivery Phase 2 evidence plan, runs only the
  planned read-only smoke probes whose prerequisites are present, and emits a
  bounded preflight report metadata packet. It does not store raw provider
  output, pass write/destructive flags, mutate workflow state, approve
  production, or enable gates.
  """

  @behaviour SymphonyElixir.Workflow.Extension.OperatorCommand

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.OperatorCommand
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.PreflightReportCollector

  @command_id "symphony.workflow.extension.coding_pr_delivery.production_profile_preflight_collect"
  @schema "coding_pr_delivery.production_profile_preflight_collect_result.v1"
  @usage_error_exit_code 64
  @internal_error_exit_code 70
  @validation_failed_exit_code 1
  @switches [
    plan: :string,
    plan_id: :string,
    repo: :string,
    pr: :string,
    tapd_cnb_shadow_run_id: :string,
    linear_cnb_shadow_run_id: :string,
    evidence_prefix: :string,
    json: :boolean,
    pretty: :boolean,
    help: :boolean
  ]

  @type deps :: %{
          required(:collect_preflight_report) => (String.t(), keyword() -> {:ok, map()} | {:error, map()})
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
      collect_preflight_report: fn plan, opts ->
        with {:ok, phase2_plan} <- ProductionProfile.phase2_evidence_plan(plan, opts) do
          PreflightReportCollector.collect(phase2_plan, opts)
        end
      end
    }
  end

  defp evaluate_argv(argv, deps) do
    case OptionParser.parse(argv, strict: @switches, aliases: [h: :help]) do
      {parsed_opts, [], []} ->
        if parsed_opts[:help] do
          {usage(), "", 0}
        else
          collect_preflight(parsed_opts, deps)
        end

      {_opts, unexpected, []} ->
        {"", "Unexpected argument count: #{length(unexpected)}\n" <> usage(), @usage_error_exit_code}

      {_opts, _argv, invalid} ->
        {"", "Invalid option count: #{length(invalid)}\n" <> usage(), @usage_error_exit_code}
    end
  end

  defp collect_preflight(parsed_opts, deps) do
    plan = parsed_opts |> Keyword.get(:plan, "tiered_reference") |> String.trim()

    case deps.collect_preflight_report.(plan, collect_opts(parsed_opts)) do
      {:ok, report} ->
        result = collect_result(report, true, Map.get(report, "status"), [])
        {Jason.encode!(result, pretty: Keyword.get(parsed_opts, :pretty, false)) <> "\n", "", 0}

      {:error, reason} ->
        result = collect_result(nil, false, "invalid", errors(reason))
        {Jason.encode!(result, pretty: Keyword.get(parsed_opts, :pretty, false)) <> "\n", "", @validation_failed_exit_code}
    end
  end

  defp collect_opts(parsed_opts) do
    []
    |> maybe_put(:plan_id, parsed_opts[:plan_id])
    |> maybe_put(:repo_slug, parsed_opts[:repo])
    |> maybe_put(:change_proposal_number, parsed_opts[:pr])
    |> maybe_put(:tapd_cnb_shadow_run_id, parsed_opts[:tapd_cnb_shadow_run_id])
    |> maybe_put(:linear_cnb_shadow_run_id, parsed_opts[:linear_cnb_shadow_run_id])
    |> maybe_put(:evidence_prefix, parsed_opts[:evidence_prefix])
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp collect_result(report, valid?, status, errors) do
    %{
      "schema" => @schema,
      "kind" => "preflight_report",
      "status" => status,
      "valid" => valid?,
      "preflight_report_schema" => template_schema(report),
      "preflight_report" => report,
      "summary" => summary(report),
      "errors" => errors,
      "raw_output_included" => false,
      "does_call_read_only_providers_when_prerequisites_present" => true,
      "does_not_pass_write_or_destructive_flags" => true,
      "does_not_read_evidence_files" => true,
      "does_not_mutate_workflow_state" => true,
      "does_not_approve_production" => true,
      "does_not_enable_production" => true
    }
  end

  defp template_schema(report) when is_map(report), do: Map.get(report, "schema")
  defp template_schema(_report), do: nil

  defp summary(report) when is_map(report) do
    %{
      "phase2_plan_kind" => value_at(report, ["phase2_evidence_plan", "plan_kind"]),
      "status" => Map.get(report, "status"),
      "planned_preflight_command_count" => Map.get(report, "planned_preflight_command_count"),
      "preflight_result_count" => Map.get(report, "preflight_result_count"),
      "raw_output_included" => Map.get(report, "raw_output_included")
    }
  end

  defp summary(_report), do: %{}

  defp errors(%{errors: errors}) when is_list(errors), do: Enum.map(errors, &error_to_map/1)
  defp errors(%{"errors" => errors}) when is_list(errors), do: Enum.map(errors, &error_to_map/1)
  defp errors(reason), do: [error_to_map(reason)]

  defp error_to_map(error) when is_map(error) do
    error
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp error_to_map(_error), do: %{"code" => "preflight_collect_error", "message" => "Preflight collection failed."}

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

  defp validate_deps(%{collect_preflight_report: collect}) when is_function(collect, 2), do: :ok
  defp validate_deps(deps), do: {:error, {:deps_invalid, Diagnostics.type_name(deps)}}

  defp first_invalid_type(argv) do
    argv
    |> Enum.find(&(not is_binary(&1)))
    |> Diagnostics.type_name()
  end

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

  defp format_usage_error({:argv_not_list, type}), do: "Command argv must be a list of strings: value_type=#{type}"
  defp format_usage_error({:argv_contains_non_string, type}), do: "Command argv must contain only strings: value_type=#{type}"

  defp format_internal_error({:command_opts_not_keyword, type}),
    do: "Coding PR Delivery operator command options are invalid: reason=command_opts_not_keyword value_type=#{type}\n"

  defp format_internal_error({:deps_invalid, type}),
    do: "Coding PR Delivery operator command options are invalid: reason=deps_invalid value_type=#{type}\n"

  defp usage do
    """
    Command arguments:
      [--plan <id>] [--repo <owner/name>] [--pr <number>] [--json|--pretty]
      [--tapd-cnb-shadow-run-id <id>] [--linear-cnb-shadow-run-id <id>]
      [--evidence-prefix evidence/preflight]

    Supported plans:
      tiered_reference
      linear_github_ready
      tapd_cnb_shadow
      linear_cnb_shadow

    This command runs planned read-only provider preflight smoke probes only
    when prerequisites are present, then emits bounded preflight report
    metadata. It does not pass write/destructive flags, store raw provider
    output, mutate workflow state, approve production, or enable gates.
    """
  end
end
