defmodule SymphonyElixir.CLI.ChangeProposalReconcile do
  @moduledoc false

  alias SymphonyElixir.ChangeProposalReconciliation.OneShot

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

  @spec evaluate([String.t()], deps()) :: {String.t(), String.t(), non_neg_integer()}
  def evaluate(argv, deps \\ runtime_deps()) when is_list(argv) and is_map(deps) do
    case OptionParser.parse(argv, strict: @switches, aliases: [h: :help]) do
      {opts, [], []} ->
        if opts[:help] do
          {usage(), "", 0}
        else
          case validate_opts(opts) do
            :ok -> render_one_shot(opts, deps)
            {:error, message} -> {"", message <> "\n" <> usage(), 64}
          end
        end

      {_opts, unexpected, []} ->
        {"", "Unexpected argument(s): #{inspect(unexpected)}\n" <> usage(), 64}

      {_opts, _argv, invalid} ->
        {"", "Invalid option(s): #{inspect(invalid)}\n" <> usage(), 64}
    end
  end

  @spec runtime_deps() :: deps()
  def runtime_deps do
    %{
      one_shot_run: fn opts -> OneShot.run(opts) end
    }
  end

  defp render_one_shot(opts, deps) do
    report =
      opts
      |> one_shot_opts()
      |> deps.one_shot_run.()

    output =
      if opts[:json] do
        Jason.encode!(OneShot.to_map(report)) <> "\n"
      else
        OneShot.format_text(report)
      end

    {output, "", if(report.ok, do: 0, else: 1)}
  end

  defp one_shot_opts(opts) do
    [
      workflow_path: opts[:workflow],
      template: opts[:template],
      issue_id: opts[:issue],
      confirm_state_write: Keyword.get(opts, :confirm_state_write, false)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp validate_opts(opts) do
    cond do
      present?(opts[:workflow]) and present?(opts[:template]) ->
        {:error, "Pass either --workflow or --template, not both"}

      not present?(opts[:issue]) ->
        {:error, "--issue is required"}

      true ->
        :ok
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp usage do
    """
    Usage:
      mix change_proposal.reconcile [--workflow <path>|--template <alias>] --issue <id> [--json]
      mix change_proposal.reconcile [--workflow <path>|--template <alias>] --issue <id> --confirm-state-write [--json]

    By default this operator command is dry-run:
      - validates the workflow reconciliation config
      - fetches exactly the supplied issue id
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
