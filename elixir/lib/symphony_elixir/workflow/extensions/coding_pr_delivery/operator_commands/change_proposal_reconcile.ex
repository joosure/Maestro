defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ChangeProposalReconcile do
  @moduledoc """
  Operator command for targeted Coding PR Delivery reconciliation.

  The command owns change-proposal-specific argument validation, output
  rendering, and one-shot execution. Platform CLI entrypoints dispatch to this
  module through the workflow extension operator-command registry.
  """

  @behaviour SymphonyElixir.Workflow.Extension.OperatorCommand

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.OperatorCommand
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot

  @command_id "symphony.workflow.extension.coding_pr_delivery.change_proposal_reconcile"
  @usage_error_exit_code 64
  @internal_error_exit_code 70

  @switches [
    workflow: :string,
    template: :string,
    issue: :string,
    confirm_state_write: :boolean,
    json: :boolean,
    help: :boolean
  ]

  @type deps :: %{
          required(:one_shot_run) => (keyword() -> OneShot.report())
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
      one_shot_run: fn opts -> OneShot.run(opts) end
    }
  end

  defp evaluate_argv(argv, deps) do
    case OptionParser.parse(argv, strict: @switches, aliases: [h: :help]) do
      {parsed_opts, [], []} ->
        if parsed_opts[:help] do
          {usage(), "", 0}
        else
          case validate_opts(parsed_opts) do
            :ok -> render_one_shot(parsed_opts, deps)
            {:error, message} -> {"", message <> "\n" <> usage(), @usage_error_exit_code}
          end
        end

      {_opts, unexpected, []} ->
        {"", "Unexpected argument count: #{length(unexpected)}\n" <> usage(), @usage_error_exit_code}

      {_opts, _argv, invalid} ->
        {"", "Invalid option count: #{length(invalid)}\n" <> usage(), @usage_error_exit_code}
    end
  end

  defp render_one_shot(parsed_opts, deps) do
    report =
      parsed_opts
      |> one_shot_opts()
      |> deps.one_shot_run.()

    output =
      if parsed_opts[:json] do
        Jason.encode!(OneShot.to_map(report)) <> "\n"
      else
        OneShot.format_text(report)
      end

    {output, "", if(report.ok, do: 0, else: 1)}
  end

  defp one_shot_opts(parsed_opts) do
    [
      workflow_path: parsed_opts[:workflow],
      template: parsed_opts[:template],
      issue_id: parsed_opts[:issue],
      confirm_state_write: Keyword.get(parsed_opts, :confirm_state_write, false)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp validate_opts(parsed_opts) do
    cond do
      present?(parsed_opts[:workflow]) and present?(parsed_opts[:template]) ->
        {:error, "Pass either --workflow or --template, not both"}

      not present?(parsed_opts[:issue]) ->
        {:error, "--issue is required"}

      true ->
        :ok
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

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

  defp validate_deps(%{one_shot_run: one_shot_run}) when is_function(one_shot_run, 1), do: :ok

  defp validate_deps(%{one_shot_run: one_shot_run}),
    do: {:error, {:one_shot_run_not_function, Diagnostics.type_name(one_shot_run)}}

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

  defp format_internal_error({:one_shot_run_not_function, type}),
    do: "Coding PR Delivery operator command options are invalid: reason=one_shot_run_not_function value_type=#{type}\n"

  defp usage do
    """
    Command arguments:
      [--workflow <path>|--template <alias>] --issue <id> [--json]
      [--workflow <path>|--template <alias>] --issue <id> --confirm-state-write [--json]

    By default this operator command is dry-run:
      - validates the workflow reconciliation config
      - fetches exactly the supplied issue id
      - loads workflow-local structured KnownTarget records from workflow
        extension state
      - runs targeted reconciliation without source-route scans
      - does not write tracker state

    State-write mode:
      --confirm-state-write
                             Explicitly opt into the tracker state transition
                             selected by change-proposal reconciliation.

    Workflow selection:
      --workflow <path>      Load a concrete WORKFLOW.md file.
      --template <alias>     Load a bundled workflow template alias.
      --issue <id>           Process this issue id. Required.
      --json                 Emit machine-readable JSON instead of text.
    """
  end
end
