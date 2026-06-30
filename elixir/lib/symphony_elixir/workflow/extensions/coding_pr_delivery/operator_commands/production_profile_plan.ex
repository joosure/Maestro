defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfilePlan do
  @moduledoc """
  Operator command for Coding PR Delivery production-profile plan export.

  The command owns Coding PR Delivery production-plan argument validation and
  rendering. Platform CLI entrypoints dispatch to this module through the
  workflow extension operator-command registry.
  """

  @behaviour SymphonyElixir.Workflow.Extension.OperatorCommand

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.OperatorCommand
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile

  @command_id "symphony.workflow.extension.coding_pr_delivery.production_profile_plan"
  @usage_error_exit_code 64
  @internal_error_exit_code 70
  @switches [
    phase: :string,
    plan: :string,
    plan_id: :string,
    tapd_cnb_shadow_run_id: :string,
    linear_cnb_shadow_run_id: :string,
    json: :boolean,
    pretty: :boolean,
    help: :boolean
  ]
  @phases ["phase2", "phase4"]

  @type deps :: %{
          required(:phase2_evidence_plan) => (String.t(), keyword() -> {:ok, map()} | {:error, map()}),
          required(:phase4_review_plan) => (String.t(), keyword() -> {:ok, map()} | {:error, map()})
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
      phase2_evidence_plan: fn plan, opts -> ProductionProfile.phase2_evidence_plan(plan, opts) end,
      phase4_review_plan: fn plan, opts -> ProductionProfile.phase4_review_plan(plan, opts) end
    }
  end

  defp evaluate_argv(argv, deps) do
    case OptionParser.parse(argv, strict: @switches, aliases: [h: :help]) do
      {parsed_opts, [], []} ->
        if parsed_opts[:help] do
          {usage(), "", 0}
        else
          render_plan(parsed_opts, deps)
        end

      {_opts, unexpected, []} ->
        {"", "Unexpected argument count: #{length(unexpected)}\n" <> usage(), @usage_error_exit_code}

      {_opts, _argv, invalid} ->
        {"", "Invalid option count: #{length(invalid)}\n" <> usage(), @usage_error_exit_code}
    end
  end

  defp render_plan(parsed_opts, deps) do
    phase = parsed_opts |> Keyword.get(:phase, "phase2") |> String.trim()
    plan = parsed_opts |> Keyword.get(:plan, "tiered_reference") |> String.trim()

    if phase in @phases do
      phase
      |> build_plan(plan, build_opts(parsed_opts), deps)
      |> render_plan_result(parsed_opts)
    else
      {"", "Unsupported phase. Expected one of: #{Enum.join(@phases, ", ")}\n" <> usage(), @usage_error_exit_code}
    end
  end

  defp build_plan("phase2", plan, opts, deps), do: deps.phase2_evidence_plan.(plan, opts)
  defp build_plan("phase4", plan, opts, deps), do: deps.phase4_review_plan.(plan, opts)

  defp build_opts(parsed_opts) do
    []
    |> maybe_put(:plan_id, parsed_opts[:plan_id])
    |> maybe_put(:tapd_cnb_shadow_run_id, parsed_opts[:tapd_cnb_shadow_run_id])
    |> maybe_put(:linear_cnb_shadow_run_id, parsed_opts[:linear_cnb_shadow_run_id])
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp render_plan_result({:ok, plan}, parsed_opts) do
    output = Jason.encode!(plan, pretty: Keyword.get(parsed_opts, :pretty, false)) <> "\n"
    {output, "", 0}
  end

  defp render_plan_result({:error, reason}, _parsed_opts) do
    message = Map.get(reason, :message) || Map.get(reason, "message") || "production-profile plan is invalid"
    {"", message <> "\n", @usage_error_exit_code}
  end

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

  defp validate_deps(%{phase2_evidence_plan: phase2, phase4_review_plan: phase4})
       when is_function(phase2, 2) and is_function(phase4, 2),
       do: :ok

  defp validate_deps(%{phase2_evidence_plan: phase2}) when not is_function(phase2, 2) do
    {:error, {:phase2_evidence_plan_not_function, Diagnostics.type_name(phase2)}}
  end

  defp validate_deps(%{phase4_review_plan: phase4}) when not is_function(phase4, 2) do
    {:error, {:phase4_review_plan_not_function, Diagnostics.type_name(phase4)}}
  end

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

  defp format_internal_error({:phase2_evidence_plan_not_function, type}),
    do: "Coding PR Delivery operator command options are invalid: reason=phase2_evidence_plan_not_function value_type=#{type}\n"

  defp format_internal_error({:phase4_review_plan_not_function, type}),
    do: "Coding PR Delivery operator command options are invalid: reason=phase4_review_plan_not_function value_type=#{type}\n"

  defp usage do
    """
    Command arguments:
      [--phase phase2|phase4] [--plan <id>] [--json|--pretty]
      [--phase phase4] [--plan linear_cnb_shadow] --linear-cnb-shadow-run-id <id> [--json|--pretty]

    Supported plans:
      tiered_reference
      linear_github_ready
      tapd_cnb_shadow
      linear_cnb_shadow

    This command exports deterministic Coding PR Delivery production-profile
    plans only. It does not collect live evidence, read evidence files, call
    providers, mutate workflow state, approve production, or enable gates.
    """
  end
end
