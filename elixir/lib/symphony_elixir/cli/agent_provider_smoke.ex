defmodule SymphonyElixir.CLI.AgentProviderSmoke do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Smoke

  @switches [
    workflow: :string,
    template: :string,
    prompt: :string,
    start_only: :boolean,
    issue_id: :string,
    issue_identifier: :string,
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
      prompt: opts[:prompt],
      run_turn: not Keyword.get(opts, :start_only, false),
      issue_id: opts[:issue_id],
      issue_identifier: opts[:issue_identifier]
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp validate_opts(opts) do
    cond do
      present?(opts[:workflow]) and present?(opts[:template]) ->
        {:error, "Pass either --workflow or --template, not both"}

      true ->
        :ok
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp usage do
    """
    Usage:
      mix agent_provider.smoke [--workflow <path>|--template <alias>] [--prompt <text>] [--start-only] [--json]

    By default this smoke runs one minimal first turn:
      - validates the workflow config
      - creates a temporary empty workspace
      - prepares provider-owned workspace tooling
      - starts the configured agent provider
      - sends a bounded smoke prompt
      - stops the session and removes the temporary workspace

    The smoke prompt is not the workflow business prompt. The runner does not
    read or write tracker issues, repositories, or repo-provider resources.

    Options:
      --workflow <path>        Load a concrete WORKFLOW.md file.
      --template <alias>       Load a bundled workflow template alias.
      --prompt <text>          Override the minimal smoke prompt.
      --start-only             Start and stop the provider without sending a turn.
      --issue-id <id>          Optional issue id metadata for provider events.
      --issue-identifier <id>  Optional issue identifier metadata for provider events.
      --json                   Emit machine-readable JSON instead of text.
    """
  end
end
