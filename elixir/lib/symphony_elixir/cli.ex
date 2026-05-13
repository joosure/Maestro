defmodule SymphonyElixir.CLI do
  @moduledoc """
  Escript entrypoint for running Symphony with an explicit WORKFLOW.md path.
  """

  alias SymphonyElixir.CLI.Accounts, as: AccountsCLI
  alias SymphonyElixir.CLI.Repo, as: RepoCLI
  alias SymphonyElixir.CLI.RepoProvider, as: RepoProviderCLI
  alias SymphonyElixir.Config
  alias SymphonyElixir.Observability.LogFile
  alias SymphonyElixir.RepoProvider.Error, as: RepoProviderError
  alias SymphonyElixir.Tracker.Error, as: TrackerError
  alias SymphonyElixir.Workflow.Templates, as: WorkflowTemplates
  alias SymphonyWorkerDaemon.CLI, as: WorkerDaemonCLI

  @acknowledgement_switch :i_understand_that_this_will_be_running_without_the_usual_guardrails
  @switches [{@acknowledgement_switch, :boolean}, logs_root: :string, port: :integer, template: :string]

  @type ensure_started_result :: {:ok, [atom()]} | {:error, term()}
  @type deps :: %{
          required(:file_regular?) => (String.t() -> boolean()),
          required(:set_workflow_file_path) => (String.t() -> :ok | {:error, term()}),
          required(:set_logs_root) => (String.t() -> :ok | {:error, term()}),
          required(:set_server_port_override) => (non_neg_integer() | nil -> :ok | {:error, term()}),
          required(:validate_config) => (-> :ok | {:error, term()}),
          required(:ensure_all_started) => (-> ensure_started_result()),
          optional(:worker_daemon_evaluate) => ([String.t()] -> :ok | {:error, String.t()}),
          optional(:accounts_login) => (String.t(), String.t(), keyword() -> {:ok, map()} | {:error, term()}),
          optional(:accounts_import) => (String.t(), String.t(), keyword() -> {:ok, map()} | {:error, term()}),
          optional(:accounts_list) => (String.t() | nil -> {:ok, [map()]} | {:error, term()}),
          optional(:accounts_verify) => (String.t(), String.t(), keyword() -> {:ok, map()} | {:error, term()}),
          optional(:accounts_pause) => (String.t(), String.t(), keyword() -> {:ok, map()} | {:error, term()}),
          optional(:accounts_resume) => (String.t(), String.t() -> {:ok, map()} | {:error, term()}),
          optional(:accounts_remove) => (String.t(), String.t() -> :ok | {:error, term()}),
          optional(:accounts_enable) => (String.t(), String.t() -> {:ok, map()} | {:error, term()}),
          optional(:accounts_disable) => (String.t(), String.t() -> {:ok, map()} | {:error, term()})
        }

  @spec main([String.t()]) :: no_return()
  def main(["repo-provider" | rest]) do
    RepoProviderCLI.main(rest)
  end

  def main(["repo" | rest]) do
    RepoCLI.main(rest)
  end

  def main(["worker-daemon" | rest]) do
    WorkerDaemonCLI.main(rest)
  end

  def main(args) do
    case evaluate(args) do
      :ok ->
        if accounts_command?(args), do: System.halt(0), else: wait_for_shutdown()

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  defp accounts_command?(["accounts" | _args]), do: true
  defp accounts_command?(_args), do: false

  @spec evaluate([String.t()], deps()) :: :ok | {:error, String.t()}
  def evaluate(args, deps \\ runtime_deps())

  def evaluate(["accounts" | account_args], deps) do
    AccountsCLI.evaluate(account_args, deps, usage_message())
  end

  def evaluate(["worker-daemon" | daemon_args], deps) do
    Map.get(deps, :worker_daemon_evaluate, &WorkerDaemonCLI.evaluate/1).(daemon_args)
  end

  def evaluate(args, deps) do
    case OptionParser.parse(args, strict: @switches) do
      {opts, workflow_args, []} ->
        with :ok <- require_guardrails_acknowledgement(opts),
             :ok <- maybe_set_logs_root(opts, deps),
             :ok <- maybe_set_server_port(opts, deps),
             {:ok, workflow_path} <- workflow_path(opts, workflow_args) do
          run(workflow_path, deps)
        end

      _ ->
        {:error, usage_message()}
    end
  end

  @spec run(String.t(), deps()) :: :ok | {:error, String.t()}
  def run(workflow_path, deps) do
    expanded_path = Path.expand(workflow_path)

    if deps.file_regular?.(expanded_path) do
      :ok = deps.set_workflow_file_path.(expanded_path)

      case deps.validate_config.() do
        :ok ->
          case deps.ensure_all_started.() do
            {:ok, _started_apps} ->
              :ok

            {:error, reason} ->
              {:error, "Failed to start Symphony with workflow #{expanded_path}: #{inspect(reason)}"}
          end

        {:error, reason} ->
          {:error, format_config_error(reason)}
      end
    else
      {:error, "Workflow file not found: #{expanded_path}"}
    end
  end

  defp workflow_path(opts, workflow_args) do
    template_values = Keyword.get_values(opts, :template)

    cond do
      length(template_values) > 1 ->
        {:error, "Pass only one workflow template alias"}

      template_values != [] and workflow_args != [] ->
        {:error, "Pass either --template or a workflow path, not both"}

      length(workflow_args) > 1 ->
        {:error, usage_message()}

      template_values != [] ->
        WorkflowTemplates.resolve(List.last(template_values))

      workflow_args == [] ->
        {:ok, Path.expand("WORKFLOW.md")}

      true ->
        {:ok, List.first(workflow_args)}
    end
  end

  @spec usage_message() :: String.t()
  defp usage_message do
    """
    Usage:
      symphony [--logs-root <path>] [--port <port>] [--template <alias>]
      symphony [--logs-root <path>] [--port <port>] [path-to-WORKFLOW.md]
      symphony accounts login claude_code <id> [--email <email>] [--token-stdin|--token-file <path>|--token-env <VAR>] [path-to-WORKFLOW.md]
      symphony accounts login opencode <id> --env-name <MODEL_PROVIDER_API_KEY_ENV> [--email <email>] [--token-stdin|--token-file <path>|--token-env <VAR>] [path-to-WORKFLOW.md]
      symphony accounts import claude_code <id> [--email <email>] [--from <CLAUDE_CONFIG_DIR>] [path-to-WORKFLOW.md]
      symphony accounts list [provider] [path-to-WORKFLOW.md]
      symphony accounts verify <provider> <id> [path-to-WORKFLOW.md]
      symphony accounts pause <provider> <id> [--until <timestamp>] [--reason <text>] [path-to-WORKFLOW.md]
      symphony accounts resume <provider> <id> [path-to-WORKFLOW.md]
      symphony accounts enable <provider> <id> [path-to-WORKFLOW.md]
      symphony accounts disable <provider> <id> [path-to-WORKFLOW.md]
      symphony accounts remove <provider> <id> [path-to-WORKFLOW.md]
      symphony worker-daemon --workspace-root <path> [--host 127.0.0.1] [--port 4001] [--token-env SYMPHONY_WORKER_DAEMON_TOKEN]

    Provider aliases accepted for operator convenience: claude -> claude_code, opencode -> opencode.
    """
    |> String.trim()
  end

  @spec runtime_deps() :: deps()
  defp runtime_deps do
    %{
      file_regular?: &File.regular?/1,
      set_workflow_file_path: &SymphonyElixir.Workflow.set_workflow_file_path/1,
      set_logs_root: &set_logs_root/1,
      set_server_port_override: &set_server_port_override/1,
      validate_config: &Config.validate!/0,
      ensure_all_started: fn -> Application.ensure_all_started(:symphony_elixir) end,
      worker_daemon_evaluate: &WorkerDaemonCLI.evaluate/1
    }
    |> Map.merge(AccountsCLI.runtime_deps())
  end

  defp maybe_set_logs_root(opts, deps) do
    case Keyword.get_values(opts, :logs_root) do
      [] ->
        :ok

      values ->
        logs_root = values |> List.last() |> String.trim()

        if logs_root == "" do
          {:error, usage_message()}
        else
          :ok = deps.set_logs_root.(Path.expand(logs_root))
        end
    end
  end

  defp require_guardrails_acknowledgement(opts) do
    if Keyword.get(opts, @acknowledgement_switch, false) do
      :ok
    else
      {:error, acknowledgement_banner()}
    end
  end

  @spec acknowledgement_banner() :: String.t()
  defp acknowledgement_banner do
    lines = [
      "This Symphony implementation is a low key engineering preview.",
      "The configured agent provider will run without any guardrails.",
      "SymphonyElixir is not a supported product and is presented as-is.",
      "To proceed, start with `--i-understand-that-this-will-be-running-without-the-usual-guardrails` CLI argument"
    ]

    width = Enum.max(Enum.map(lines, &String.length/1))
    border = String.duplicate("─", width + 2)
    top = "╭" <> border <> "╮"
    bottom = "╰" <> border <> "╯"
    spacer = "│ " <> String.duplicate(" ", width) <> " │"

    content =
      [
        top,
        spacer
        | Enum.map(lines, fn line ->
            "│ " <> String.pad_trailing(line, width) <> " │"
          end)
      ] ++ [spacer, bottom]

    [
      IO.ANSI.red(),
      IO.ANSI.bright(),
      Enum.join(content, "\n"),
      IO.ANSI.reset()
    ]
    |> IO.iodata_to_binary()
  end

  defp set_logs_root(logs_root) do
    Application.put_env(:symphony_elixir, :log_file, LogFile.default_log_file(logs_root))
    :ok
  end

  defp maybe_set_server_port(opts, deps) do
    case Keyword.get_values(opts, :port) do
      [] ->
        :ok

      values ->
        port = List.last(values)

        if is_integer(port) and port >= 0 do
          :ok = deps.set_server_port_override.(port)
        else
          {:error, usage_message()}
        end
    end
  end

  defp set_server_port_override(port) when is_integer(port) and port >= 0 do
    Application.put_env(:symphony_elixir, :server_port_override, port)
    :ok
  end

  defp format_config_error(reason) do
    detail =
      case reason do
        %TrackerError{operation: :validate_config, message: message} when is_binary(message) and message != "" ->
          message

        %RepoProviderError{operation: :validate_config, message: message} when is_binary(message) and message != "" ->
          message

        _other ->
          inspect(reason)
      end

    "Configuration error: #{detail}\nCheck your WORKFLOW.md tracker and repo provider settings."
  end

  @spec wait_for_shutdown() :: no_return()
  defp wait_for_shutdown do
    case Process.whereis(SymphonyElixir.Supervisor) do
      nil ->
        IO.puts(:stderr, "Symphony supervisor is not running")
        System.halt(1)

      pid ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, reason} ->
            case reason do
              :normal -> System.halt(0)
              _ -> System.halt(1)
            end
        end
    end
  end
end
