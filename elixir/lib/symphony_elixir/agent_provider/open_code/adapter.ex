defmodule SymphonyElixir.AgentProvider.OpenCode.Adapter do
  @moduledoc """
  Agent provider adapter for OpenCode HTTP/SSE app-server runs.
  """

  @behaviour SymphonyElixir.AgentProvider.Adapter

  alias SymphonyElixir.Agent.Credential.{Lease, Material}
  alias SymphonyElixir.AgentProvider.{Config, Kinds, Session, TurnResult}
  alias SymphonyElixir.AgentProvider.OpenCode.{AppServer, CredentialEnv, Error, EventSummaryMapper, Settings, Tooling}
  alias SymphonyElixir.Workflow.CapabilityNames

  @provider_kind Kinds.opencode()
  @env_token_credential_kind CredentialEnv.env_token_credential_kind()

  @impl true
  def kind, do: @provider_kind

  @impl true
  def defaults, do: Settings.defaults()

  @impl true
  def capabilities do
    [
      CapabilityNames.agent_turn_run(),
      CapabilityNames.agent_session_stateful(),
      CapabilityNames.agent_events_streaming(),
      CapabilityNames.agent_usage_metrics(),
      CapabilityNames.agent_credentials_managed()
    ]
  end

  @impl true
  def validate_options(options), do: Settings.validate_options(options)

  @impl true
  def finalize_options(options) when is_map(options), do: Settings.finalize_options(options)

  @impl true
  def validate_config(%Config{options: options}), do: validate_options(options)
  def validate_config(_config), do: {:error, :invalid_open_code_agent_provider_config}

  @impl true
  @spec materialize_credential(Config.t(), Lease.t(), keyword()) :: {:ok, Material.t()} | {:error, term()}
  def materialize_credential(%Config{}, %Lease{} = lease, _opts \\ []) do
    case lease.metadata[:account] || lease.metadata["account"] do
      %{credential_kind: @env_token_credential_kind} = account ->
        with {:ok, env_name} <- opencode_env_name(account),
             {:ok, token} <- read_token(account) do
          {:ok, Material.new(CredentialEnv.env_token_material(env_name, token, lease.account_id))}
        end

      nil ->
        {:error, :missing_managed_credential_account}

      account ->
        {:error, {:unsupported_opencode_credential_kind, Map.get(account, :credential_kind)}}
    end
  end

  @impl true
  def prepare_workspace(%Config{}, workspace, opts \\ []) do
    case Tooling.prepare_workspace(workspace, opts) do
      :ok -> :ok
      {:error, reason} -> {:error, Error.normalize(reason, :prepare_workspace)}
    end
  end

  @impl true
  @spec start_session(Config.t(), Path.t(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  def start_session(%Config{} = config, workspace, opts \\ []) do
    settings = Settings.from_options(config.options)

    case AppServer.start_session(workspace, Keyword.put(opts, :open_code_settings, settings)) do
      {:ok, session} -> {:ok, wrap_session(session)}
      {:error, reason} -> {:error, Error.normalize(reason, :start_session)}
    end
  end

  @impl true
  @spec run_turn(Config.t(), Session.t(), String.t(), map(), keyword()) :: {:ok, TurnResult.t()} | {:error, term()}
  def run_turn(%Config{}, %Session{provider_state: session}, prompt, issue, opts \\ []) do
    case AppServer.run_turn(session, prompt, issue, opts) do
      {:ok, result} -> {:ok, TurnResult.new(result)}
      {:error, reason} -> {:error, Error.normalize(reason, :run_turn)}
    end
  end

  @impl true
  @spec stop_session(Config.t(), Session.t(), keyword()) :: :ok
  def stop_session(%Config{}, %Session{provider_state: session}, opts \\ []) do
    AppServer.stop_session(session, opts)
  end

  @impl true
  def session_stop_options(%Config{}, _result, _issue), do: []

  @impl true
  def failed_session_stop_options(%Config{}, _issue, _error), do: []

  @impl true
  def summarize_message(message), do: EventSummaryMapper.summarize(message)

  @impl true
  def session_log_event?(component, event) when is_binary(component) and is_binary(event) do
    String.starts_with?(component, "agent_provider.opencode") or String.starts_with?(event, "opencode_")
  end

  @impl true
  def workspace_automation_destination_dir, do: ".opencode"

  defp opencode_env_name(account) when is_map(account) do
    env_name = Map.get(account, :env_name) || Map.get(account, "env_name")

    cond do
      not is_binary(env_name) or String.trim(env_name) == "" ->
        {:error, :missing_opencode_env_name}

      CredentialEnv.valid_env_name?(env_name) ->
        {:ok, env_name}

      true ->
        {:error, {:invalid_opencode_env_name, env_name}}
    end
  end

  defp read_token(%{secret_file: path}) when is_binary(path) do
    case File.read(path) do
      {:ok, contents} ->
        case String.trim(contents) do
          "" -> {:error, :missing_opencode_token}
          token -> {:ok, token}
        end

      {:error, reason} ->
        {:error, {:opencode_token_read, reason}}
    end
  end

  defp read_token(_account), do: {:error, :missing_opencode_token}

  @spec wrap_session(AppServer.session()) :: Session.t()
  defp wrap_session(session) do
    Session.new(%{
      agent_provider_kind: session.agent_provider_kind,
      provider_state: session,
      agent_process_pid: Map.get(session.metadata, :agent_process_pid),
      run_id: session.run_id,
      session_id: session.session_id,
      thread_id: session.thread_id,
      workspace: session.workspace,
      worker_host: session.worker_host,
      metadata: session.metadata
    })
  end
end
