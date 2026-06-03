defmodule SymphonyElixir.AgentProvider.Codex.Adapter do
  @moduledoc """
  Agent provider adapter for Codex app-server.
  """

  @behaviour SymphonyElixir.AgentProvider.Adapter

  alias SymphonyElixir.Agent.Credential, as: AgentCredential
  alias SymphonyElixir.Agent.Credential.{Lease, Material}
  alias SymphonyElixir.Agent.Credential.Store
  alias SymphonyElixir.Observability.Redaction
  alias SymphonyElixir.Workflow.CapabilityNames

  alias SymphonyElixir.AgentProvider.Codex.{
    AppServer,
    Credential,
    CredentialEnv,
    Error,
    EventSummaryMapper,
    FailureClassifier,
    ReleaseCredentialPreflight,
    Settings,
    Tooling
  }

  alias SymphonyElixir.AgentProvider.{Config, Kinds, Session, TurnResult}

  @provider_kind Kinds.codex()
  @api_key_credential_kind CredentialEnv.api_key_credential_kind()
  @secret_mode 0o600

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
      CapabilityNames.agent_tools_dynamic(),
      CapabilityNames.agent_runtime_remote_worker(),
      CapabilityNames.agent_credentials_managed()
    ]
  end

  @impl true
  def validate_options(options) when is_map(options), do: Settings.validate_options(options)

  @impl true
  def finalize_options(options) when is_map(options), do: Settings.finalize_options(options)

  @impl true
  def validate_config(%Config{options: options}), do: validate_options(options)
  def validate_config(_config), do: {:error, :invalid_codex_agent_provider_config}

  @impl true
  def prepare_workspace(%Config{}, _workspace, _opts \\ []), do: :ok

  @impl true
  def dynamic_tool_inventory_opts, do: Tooling.dynamic_tool_inventory_opts()

  @impl true
  def release_credential_preflight_plan, do: ReleaseCredentialPreflight

  @impl true
  @spec account_login(String.t(), keyword(), keyword() | map() | nil) :: {:ok, map()} | {:error, term()}
  def account_login(id, opts, store_opts) when is_binary(id) and is_list(opts) do
    with {:ok, api_key} <- codex_api_key(opts) do
      attrs = account_attrs(opts, credential_kind: @api_key_credential_kind)

      with {:ok, account} <- Store.create_or_update(@provider_kind, id, attrs, store_opts),
           :ok <- write_secret(account.secret_file, api_key),
           {:ok, account} <- Store.create_or_update(@provider_kind, id, attrs, store_opts) do
        {:ok, account}
      end
    end
  end

  @impl true
  @spec account_verify(map(), keyword(), keyword() | map() | nil) :: {:ok, map()} | {:error, term()}
  def account_verify(%{credential_kind: @api_key_credential_kind} = account, opts, _store_opts) when is_list(opts) do
    command = Keyword.get(opts, :command) || @provider_kind

    with {:ok, material} <- materialize_verify_account(account, opts) do
      try do
        command
        |> run_provider(["login", "status"], material_env_list(material), opts)
        |> case do
          {:ok, output} -> {:ok, %{account: Store.account_summary(account), output: String.trim(output)}}
          {:error, reason} -> {:error, reason}
        end
      after
        _ = AgentCredential.cleanup_material(material)
      end
    end
  end

  def account_verify(%{credential_kind: credential_kind}, _opts, _store_opts) do
    {:error, {:unsupported_codex_credential_kind, credential_kind}}
  end

  @impl true
  @spec materialize_credential(Config.t(), Lease.t(), keyword()) :: {:ok, Material.t()} | {:error, term()}
  def materialize_credential(%Config{}, %Lease{} = lease, opts \\ []) do
    case lease.metadata[:account] || lease.metadata["account"] do
      %{credential_kind: @api_key_credential_kind} = account ->
        Credential.materialize_api_key(account, lease, opts)

      nil ->
        {:error, :missing_managed_credential_account}

      account ->
        {:error, {:unsupported_codex_credential_kind, Map.get(account, :credential_kind)}}
    end
  end

  @impl true
  @spec start_session(Config.t(), Path.t(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  def start_session(%Config{} = config, workspace, opts \\ []) do
    codex_settings = Settings.from_options(config.options)

    case AppServer.start_session(workspace, Keyword.put(opts, :codex_settings, codex_settings)) do
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
  def session_stop_options(%Config{}, result, issue) do
    FailureClassifier.session_stop_options(result, issue)
  end

  @impl true
  def failed_session_stop_options(%Config{}, issue, error) when is_binary(error) do
    FailureClassifier.failed_session_stop_options(issue, error)
  end

  @impl true
  def summarize_message(message), do: EventSummaryMapper.summarize(message)

  @impl true
  def session_log_event?(component, event) when is_binary(component) and is_binary(event) do
    String.starts_with?(component, "codex.") or String.starts_with?(event, "codex_")
  end

  @impl true
  def workspace_automation_destination_dir, do: ".codex"

  defp materialize_verify_account(account, opts) do
    lease =
      Lease.new(%{
        id: "agent-credential-codex-" <> account.id <> "-verify-" <> Integer.to_string(System.unique_integer([:positive])),
        provider_kind: @provider_kind,
        account_id: account.id,
        credential_ref_summary: Store.credential_ref(account),
        metadata: %{account: account}
      })

    Credential.materialize_api_key(account, lease, opts)
  end

  defp material_env_list(%Material{env: env}) when is_map(env), do: Enum.map(env, fn {key, value} -> {key, value} end)

  defp account_attrs(opts, extra_attrs) do
    opts
    |> Keyword.take([:email, :worker_host, :daily_token_budget, :enabled])
    |> Keyword.merge(extra_attrs)
  end

  defp codex_api_key(opts) do
    case Keyword.get(opts, :token) do
      token when is_binary(token) ->
        token = String.trim(token)

        if token == "" do
          {:error, :missing_codex_api_key}
        else
          {:ok, token}
        end

      _token ->
        {:error, :missing_codex_api_key}
    end
  end

  defp write_secret(path, value) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, String.trim(value) <> "\n") do
      File.chmod(path, @secret_mode)
    end
  end

  defp run_provider(command, args, env, opts) do
    command_parts = shell_words(command)

    case command_parts do
      [] ->
        {:error, :missing_provider_command}

      [executable | command_args] ->
        args = command_args ++ args
        env = Enum.map(env, fn {key, value} -> {key, to_string(value)} end)

        case Keyword.get(opts, :runner) do
          runner when is_function(runner, 4) ->
            runner.(executable, args, env, opts)

          _runner ->
            case System.cmd(executable, args, env: env, stderr_to_stdout: true) do
              {output, 0} -> {:ok, IO.iodata_to_binary(output)}
              {output, status} -> {:error, %{exit_status: status, output: redact_sensitive(output)}}
            end
        end
    end
  rescue
    error -> {:error, error}
  end

  defp shell_words(command) when is_binary(command), do: String.split(command, ~r/\s+/, trim: true)

  defp redact_sensitive(output) do
    output
    |> IO.iodata_to_binary()
    |> Redaction.redact_string()
    |> String.slice(0, 4_000)
  end

  @spec wrap_session(AppServer.session()) :: Session.t()
  defp wrap_session(session) do
    Session.new(%{
      agent_provider_kind: session.agent_provider_kind,
      provider_state: session,
      run_id: session.run_id,
      thread_id: session.thread_id,
      workspace: session.workspace,
      worker_host: session.worker_host
    })
  end
end
