defmodule SymphonyElixir.CLI.TrackerSmoke do
  @moduledoc false

  alias SymphonyElixir.Tracker.Smoke

  @switches [
    workflow: :string,
    template: :string,
    issue: :string,
    confirm_state_write: :boolean,
    write_state: :string,
    expected_current_state: :string,
    json: :boolean,
    help: :boolean
  ]

  @type deps :: %{
          required(:smoke_run) => (keyword() -> Smoke.report())
        }

  @spec evaluate([String.t()], deps()) :: {String.t(), String.t(), non_neg_integer()}
  def evaluate(argv, deps \\ runtime_deps()) when is_list(argv) and is_map(deps) do
    case OptionParser.parse(argv, strict: @switches, aliases: [h: :help]) do
      {opts, [], []} ->
        if opts[:help] do
          {usage(), "", 0}
        else
          case validate_opts(opts) do
            :ok -> render_smoke(opts, deps)
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
      smoke_run: fn opts -> Smoke.run(opts) end
    }
  end

  defp render_smoke(opts, deps) do
    report =
      opts
      |> smoke_opts()
      |> deps.smoke_run.()

    output =
      if opts[:json] do
        Jason.encode!(Smoke.to_map(report)) <> "\n"
      else
        Smoke.format_text(report)
      end

    {output, "", if(report.ok, do: 0, else: 1)}
  end

  defp smoke_opts(opts) do
    [
      workflow_path: opts[:workflow],
      template: opts[:template],
      issue_id: opts[:issue],
      confirm_state_write: Keyword.get(opts, :confirm_state_write, false),
      write_state: opts[:write_state],
      expected_current_state: opts[:expected_current_state]
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp validate_opts(opts) do
    cond do
      present?(opts[:workflow]) and present?(opts[:template]) ->
        {:error, "Pass either --workflow or --template, not both"}

      Keyword.get(opts, :confirm_state_write, false) and not present?(opts[:issue]) ->
        {:error, "--confirm-state-write requires --issue"}

      present?(opts[:write_state]) and not Keyword.get(opts, :confirm_state_write, false) ->
        {:error, "--write-state requires --confirm-state-write"}

      present?(opts[:expected_current_state]) and not Keyword.get(opts, :confirm_state_write, false) ->
        {:error, "--expected-current-state requires --confirm-state-write"}

      true ->
        :ok
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp usage do
    """
    Usage:
      mix tracker.smoke [--workflow <path>|--template <alias>] [--issue <id>] [--json]
      mix tracker.smoke [--workflow <path>|--template <alias>] --issue <id> --confirm-state-write [--write-state <state>] [--expected-current-state <state>] [--json]

    By default this smoke is read-only:
      - validates the workflow tracker config
      - runs tracker healthcheck
      - optionally fetches one issue by id

    State-write mode:
      --confirm-state-write
                             Explicitly opt into a tracker state update.
      --write-state <state>  Optional target raw state. Defaults to the fetched current state.
      --expected-current-state <state>
                             Optional write precondition. Defaults to the fetched current state.

    Workflow selection:
      --workflow <path>      Load a concrete WORKFLOW.md file.
      --template <alias>     Load a bundled workflow template alias.
      --issue <id>           Fetch this issue id; required for state-write mode.
      --json                 Emit machine-readable JSON instead of text.
    """
  end
end
