defmodule Mix.Tasks.Tracker.Smoke do
  use Mix.Task

  alias SymphonyElixir.CLI.TrackerSmoke, as: TrackerSmokeCLI

  @shortdoc "Run tracker smoke probes"

  @moduledoc """
  Runs smoke validation against the active tracker configuration.

  By default this task is read-only:

    - validates workflow tracker config
    - runs tracker healthcheck
    - optionally fetches one issue by id

  State-write mode requires `--confirm-state-write` and `--issue`. The write
  always passes `expected_current_state` to the tracker adapter; if no explicit
  expected state is supplied, the smoke runner uses the fetched current state.

  Usage:

      mix tracker.smoke [--workflow <path>|--template <alias>] [--issue <id>] [--json]
      mix tracker.smoke [--workflow <path>|--template <alias>] --issue <id> --confirm-state-write [--write-state <state>] [--expected-current-state <state>] [--json]
  """

  @impl Mix.Task
  def run(args) do
    if Enum.any?(args, &(&1 in ["--help", "-h"])) do
      Mix.shell().info(@moduledoc)
    else
      with :ok <- ensure_runtime_started() do
        {stdout, stderr, exit_code} = TrackerSmokeCLI.evaluate(args)

        if stdout != "", do: IO.write(stdout)

        case exit_code do
          0 ->
            :ok

          _other ->
            message =
              stderr
              |> String.trim()
              |> case do
                "" -> "tracker.smoke failed"
                value -> value
              end

            Mix.raise(message)
        end
      end
    end
  end

  defp ensure_runtime_started do
    with {:ok, _logger_apps} <- Application.ensure_all_started(:logger),
         {:ok, _req_apps} <- Application.ensure_all_started(:req),
         {:ok, _yaml_apps} <- Application.ensure_all_started(:yaml_elixir) do
      :ok
    else
      {:error, reason} -> Mix.raise("Failed to start tracker smoke runtime dependencies: #{inspect(reason)}")
    end
  end
end
