defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfileStatus do
  @moduledoc """
  Operator command for Coding PR Delivery production-profile status projection.

  The command builds a bounded status packet from a Phase 2 plan and optional
  preflight report metadata. It does not read referenced evidence files, call
  providers, mutate workflow state, approve production, or enable gates.
  """

  @behaviour SymphonyElixir.Workflow.Extension.OperatorCommand

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.OperatorCommand
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile

  @command_id "symphony.workflow.extension.coding_pr_delivery.production_profile_status"
  @usage_error_exit_code 64
  @internal_error_exit_code 70
  @validation_failed_exit_code 1
  @switches [
    plan: :string,
    phase2_plan_file: :string,
    preflight_report_file: :string,
    plan_id: :string,
    tapd_cnb_shadow_run_id: :string,
    linear_cnb_shadow_run_id: :string,
    json: :boolean,
    pretty: :boolean,
    help: :boolean
  ]

  @type status_result :: {:ok, map()} | {:error, map()}
  @type deps :: %{
          required(:read_file) => (String.t() -> {:ok, binary()} | {:error, term()}),
          required(:production_status) => (String.t() | map(), keyword() -> status_result())
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
      production_status: fn input, opts -> ProductionProfile.production_status(input, opts) end
    }
  end

  defp evaluate_argv(argv, deps) do
    case OptionParser.parse(argv, strict: @switches, aliases: [h: :help]) do
      {parsed_opts, [], []} ->
        if parsed_opts[:help] do
          {usage(), "", 0}
        else
          render_status(parsed_opts, deps)
        end

      {_opts, unexpected, []} ->
        {"", "Unexpected argument count: #{length(unexpected)}\n" <> usage(), @usage_error_exit_code}

      {_opts, _argv, invalid} ->
        {"", "Invalid option count: #{length(invalid)}\n" <> usage(), @usage_error_exit_code}
    end
  end

  defp render_status(parsed_opts, deps) do
    with {:ok, input} <- status_input(parsed_opts, deps),
         {:ok, opts} <- status_opts(parsed_opts, deps),
         {:ok, report} <- deps.production_status.(input, opts) do
      {Jason.encode!(report, pretty: Keyword.get(parsed_opts, :pretty, false)) <> "\n", "", 0}
    else
      {:error, {:usage, message}} ->
        {"", message <> "\n" <> usage(), @usage_error_exit_code}

      {:error, reason} ->
        {Jason.encode!(status_error(reason), pretty: Keyword.get(parsed_opts, :pretty, false)) <> "\n", "", @validation_failed_exit_code}
    end
  end

  defp status_input(parsed_opts, deps) do
    case Keyword.get(parsed_opts, :phase2_plan_file) do
      nil -> {:ok, parsed_opts |> Keyword.get(:plan, "tiered_reference") |> String.trim()}
      file_path -> read_json_file(file_path, "Phase 2 plan", deps)
    end
  end

  defp status_opts(parsed_opts, deps) do
    opts =
      []
      |> maybe_put(:plan_id, parsed_opts[:plan_id])
      |> maybe_put(:tapd_cnb_shadow_run_id, parsed_opts[:tapd_cnb_shadow_run_id])
      |> maybe_put(:linear_cnb_shadow_run_id, parsed_opts[:linear_cnb_shadow_run_id])

    case Keyword.get(parsed_opts, :preflight_report_file) do
      nil ->
        {:ok, opts}

      file_path ->
        with {:ok, report} <- read_json_file(file_path, "Preflight report", deps) do
          {:ok, Keyword.put(opts, :preflight_report, report)}
        end
    end
  end

  defp read_json_file(file_path, label, deps) do
    with {:ok, contents} <- deps.read_file.(file_path),
         {:ok, decoded} <- Jason.decode(contents),
         true <- is_map(decoded) do
      {:ok, decoded}
    else
      {:error, _reason} ->
        {:error, {:usage, "#{label} file could not be read or parsed."}}

      false ->
        {:error, {:usage, "#{label} file must contain an object."}}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp status_error(reason) do
    %{
      "schema" => "coding_pr_delivery.production_profile_status_result.v1",
      "status" => "invalid",
      "valid" => false,
      "errors" => errors(reason),
      "raw_input_included" => false,
      "does_not_read_referenced_evidence_files" => true,
      "does_not_call_providers" => true,
      "does_not_mutate_workflow_state" => true,
      "does_not_approve_production" => true,
      "does_not_enable_production" => true
    }
  end

  defp errors(%{errors: errors}) when is_list(errors), do: Enum.map(errors, &error_to_map/1)
  defp errors(%{"errors" => errors}) when is_list(errors), do: Enum.map(errors, &error_to_map/1)
  defp errors(reason), do: [error_to_map(reason)]

  defp error_to_map(error) when is_map(error) do
    error
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp error_to_map(_error), do: %{"code" => "production_profile_status_error", "message" => "Status projection failed."}

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

  defp validate_deps(%{read_file: read_file, production_status: status}) when is_function(read_file, 1) and is_function(status, 2), do: :ok
  defp validate_deps(deps), do: {:error, {:deps_invalid, Diagnostics.type_name(deps)}}

  defp first_invalid_type(argv) do
    argv
    |> Enum.find(&(not is_binary(&1)))
    |> Diagnostics.type_name()
  end

  defp format_usage_error({:argv_not_list, type}), do: "Command argv must be a list of strings: value_type=#{type}"
  defp format_usage_error({:argv_contains_non_string, type}), do: "Command argv must contain only strings: value_type=#{type}"

  defp format_internal_error({:command_opts_not_keyword, type}),
    do: "Coding PR Delivery operator command options are invalid: reason=command_opts_not_keyword value_type=#{type}\n"

  defp format_internal_error({:deps_invalid, type}),
    do: "Coding PR Delivery operator command options are invalid: reason=deps_invalid value_type=#{type}\n"

  defp usage do
    """
    Command arguments:
      [--plan <id>|--phase2-plan-file <file>] [--preflight-report-file <file>] [--json|--pretty]
      [--tapd-cnb-shadow-run-id <id>] [--linear-cnb-shadow-run-id <id>]

    Supported plans:
      tiered_reference
      linear_github_ready
      tapd_cnb_shadow
      linear_cnb_shadow

    This command emits a bounded Coding PR Delivery production-profile status
    packet. It does not read referenced evidence files, call providers, mutate
    workflow state, approve production, or enable gates.
    """
  end
end
