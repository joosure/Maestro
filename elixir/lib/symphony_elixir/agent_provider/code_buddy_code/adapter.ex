defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.Adapter do
  @moduledoc """
  Agent provider adapter for the accepted CodeBuddy Code baseline.
  """

  @behaviour SymphonyElixir.AgentProvider.Adapter

  alias SymphonyElixir.Agent.Credential.Accounts.{Command, Options, Secret}
  alias SymphonyElixir.Agent.Credential.{Lease, Material}
  alias SymphonyElixir.Agent.Credential.Store
  alias SymphonyElixir.AgentProvider.CodeBuddyCode.{AppServer, CredentialEnv, Error, EventSummaryMapper, Settings, Tooling}
  alias SymphonyElixir.AgentProvider.{Config, Kinds, Session, TurnResult}
  alias SymphonyElixir.Workflow.CapabilityNames

  @provider_kind Kinds.codebuddy_code()
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
      CapabilityNames.agent_tools_dynamic(),
      CapabilityNames.agent_credentials_managed()
    ]
  end

  @impl true
  def dynamic_tool_inventory_opts, do: Tooling.dynamic_tool_inventory_opts()

  @impl true
  def validate_options(options), do: Settings.validate_options(options)

  @impl true
  def finalize_options(options) when is_map(options), do: Settings.finalize_options(options)

  @impl true
  def validate_config(%Config{options: options}), do: validate_options(options)
  def validate_config(_config), do: {:error, :invalid_codebuddy_code_agent_provider_config}

  @impl true
  @spec account_login(String.t(), keyword(), keyword() | map() | nil) :: {:ok, map()} | {:error, term()}
  def account_login(id, opts, store_opts) when is_binary(id) and is_list(opts) do
    with {:ok, api_key} <- Options.required_token(opts, :missing_codebuddy_api_key),
         {:ok, internet_environment} <- Options.codebuddy_internet_environment(opts) do
      attrs =
        Options.attrs(opts,
          credential_kind: @env_token_credential_kind,
          internet_environment: internet_environment
        )

      with {:ok, account} <- Store.create_or_update(@provider_kind, id, attrs, store_opts),
           :ok <- Secret.write(account.secret_file, api_key),
           {:ok, account} <- Store.create_or_update(@provider_kind, id, attrs, store_opts) do
        {:ok, account}
      end
    end
  end

  @impl true
  @spec account_verify(map(), keyword(), keyword() | map() | nil) :: {:ok, map()} | {:error, term()}
  def account_verify(%{credential_kind: @env_token_credential_kind} = account, opts, _store_opts) when is_list(opts) do
    command = Keyword.get(opts, :command) || "codebuddy"

    command
    |> Command.run(["--version"], CredentialEnv.env_token_env(Secret.read(account.secret_file), account.internet_environment), opts)
    |> case do
      {:ok, output} -> {:ok, %{account: Store.account_summary(account), output: String.trim(output)}}
      {:error, reason} -> {:error, reason}
    end
  end

  def account_verify(%{credential_kind: credential_kind}, _opts, _store_opts) do
    {:error, {:unsupported_codebuddy_credential_kind, credential_kind}}
  end

  @impl true
  @spec materialize_credential(Config.t(), Lease.t(), keyword()) :: {:ok, Material.t()} | {:error, term()}
  def materialize_credential(%Config{}, %Lease{} = lease, _opts \\ []) do
    case lease.metadata[:account] || lease.metadata["account"] do
      %{credential_kind: @env_token_credential_kind} = account ->
        with {:ok, api_key} <- read_api_key(account),
             {:ok, internet_environment} <- account_internet_environment(account) do
          {:ok, Material.new(CredentialEnv.env_token_material(api_key, internet_environment, lease.account_id))}
        end

      nil ->
        {:error, :missing_managed_credential_account}

      account ->
        {:error, {:unsupported_codebuddy_credential_kind, account_value(account, :credential_kind)}}
    end
  end

  @impl true
  def prepare_workspace(%Config{options: options}, workspace, opts \\ []) do
    settings = Settings.from_options(options)

    case Tooling.prepare_workspace(workspace, settings, opts) do
      :ok -> :ok
      {:error, reason} -> {:error, Error.normalize(reason, :prepare_workspace)}
    end
  end

  @impl true
  @spec start_session(Config.t(), Path.t(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  def start_session(%Config{} = config, workspace, opts \\ []) do
    case validate_options(config.options) do
      :ok ->
        settings = Settings.from_options(config.options)

        case AppServer.start_session(workspace, Keyword.put(opts, :codebuddy_code_settings, settings)) do
          {:ok, session} -> {:ok, wrap_session(session)}
          {:error, reason} -> {:error, Error.normalize(reason, :start_session)}
        end

      {:error, reason} ->
        {:error, Error.normalize(reason, :start_session)}
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
  @spec stop_session(Config.t(), Session.t(), keyword()) :: :ok | {:error, term()}
  def stop_session(%Config{}, %Session{provider_state: session}, opts \\ []) do
    AppServer.stop_session(session, opts)
  end

  @impl true
  def session_stop_options(%Config{}, _result, _issue), do: []

  @impl true
  def failed_session_stop_options(%Config{}, issue, error), do: [status: :failed, issue: issue, extra: %{error: error}]

  @impl true
  def summarize_message(message), do: EventSummaryMapper.summarize(message)

  @impl true
  def session_log_event?(component, event) when is_binary(component) and is_binary(event) do
    String.starts_with?(component, "agent_provider.codebuddy_code") or String.starts_with?(event, "codebuddy_code_")
  end

  @impl true
  def workspace_automation_destination_dir, do: ".codebuddy"

  defp account_internet_environment(account) when is_map(account) do
    account
    |> account_value(:internet_environment)
    |> CredentialEnv.normalize_internet_environment()
  end

  defp read_api_key(%{secret_file: path}) when is_binary(path) do
    case File.read(path) do
      {:ok, contents} ->
        case String.trim(contents) do
          "" -> {:error, :missing_codebuddy_api_key}
          api_key -> {:ok, api_key}
        end

      {:error, reason} ->
        {:error, {:codebuddy_api_key_read, reason}}
    end
  end

  defp read_api_key(_account), do: {:error, :missing_codebuddy_api_key}

  defp account_value(account, key) when is_map(account), do: Map.get(account, key) || Map.get(account, Atom.to_string(key))

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
