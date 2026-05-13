defmodule SymphonyElixir.AgentProvider.ClaudeCode.Adapter do
  @moduledoc """
  Agent provider adapter for Claude Code stream-json app-server runs.
  """

  @behaviour SymphonyElixir.AgentProvider.Adapter

  alias SymphonyElixir.Agent.Credential.{Lease, Material}
  alias SymphonyElixir.Agent.Quota.Snapshot
  alias SymphonyElixir.AgentProvider.ClaudeCode.{AppServer, Error, EventSummaryMapper, RateLimitProbe, Settings, Tooling}
  alias SymphonyElixir.AgentProvider.{Config, Session, TurnResult}

  @provider_kind "claude_code"

  @impl true
  def kind, do: @provider_kind

  @impl true
  def defaults, do: Settings.defaults()

  @impl true
  def capabilities do
    [
      "agent.turn.run",
      "agent.session.stateful",
      "agent.events.streaming",
      "agent.usage.metrics",
      "agent.runtime.remote_worker",
      "agent.credentials.managed",
      "agent.quota.probe"
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
  def validate_config(_config), do: {:error, :invalid_claude_code_agent_provider_config}

  @impl true
  @spec materialize_credential(Config.t(), Lease.t(), keyword()) :: {:ok, Material.t()} | {:error, term()}
  def materialize_credential(%Config{}, %Lease{} = lease, _opts \\ []) do
    case lease.metadata[:account] || lease.metadata["account"] do
      %{credential_kind: "claude_oauth_token"} = account ->
        with {:ok, token} <- read_oauth_token(account) do
          {:ok,
           Material.new(%{
             env: %{
               "CLAUDE_CODE_OAUTH_TOKEN" => token,
               "CLAUDE_CONFIG_DIR" => account.auth_dir,
               "ANTHROPIC_API_KEY" => ""
             },
             summary: %{
               credential_kind: "claude_oauth_token",
               account_id_summary: lease.account_id
             }
           })}
        end

      %{credential_kind: "claude_config"} = account ->
        {:ok,
         Material.new(%{
           env: %{
             "CLAUDE_CONFIG_DIR" => account.auth_dir,
             "ANTHROPIC_API_KEY" => ""
           },
           summary: %{
             credential_kind: "claude_config",
             account_id_summary: lease.account_id
           }
         })}

      nil ->
        {:error, :missing_managed_credential_account}

      account ->
        {:error, {:unsupported_claude_credential_kind, Map.get(account, :credential_kind)}}
    end
  end

  @impl true
  @spec quota_probe(Config.t(), Lease.t() | nil, keyword()) :: {:ok, Snapshot.t()} | {:error, term()} | :unsupported
  def quota_probe(config, lease, opts \\ [])

  def quota_probe(%Config{} = config, %Lease{} = lease, opts) do
    case lease.metadata[:account] || lease.metadata["account"] do
      account when is_map(account) ->
        settings = Settings.from_options(config.options)
        quota_probe = settings.quota_probe

        probe_opts =
          opts
          |> Keyword.put_new(:model, Map.get(quota_probe, "model"))
          |> maybe_put_timeout(Map.get(quota_probe, "timeout_ms"))

        with {:ok, rate_limits} <- RateLimitProbe.probe(account, probe_opts) do
          {:ok, quota_snapshot(config, lease, rate_limits)}
        end

      _account ->
        {:error, :missing_managed_credential_account}
    end
  end

  def quota_probe(%Config{}, nil, _opts), do: :unsupported

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

    case AppServer.start_session(workspace, Keyword.put(opts, :claude_code_settings, settings)) do
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
    String.starts_with?(component, "agent_provider.claude_code") or String.starts_with?(event, "claude_code_")
  end

  @impl true
  def workspace_automation_destination_dir, do: ".claude"

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

  defp read_oauth_token(%{secret_file: path}) when is_binary(path) do
    case File.read(path) do
      {:ok, contents} ->
        case String.trim(contents) do
          "" -> {:error, :missing_claude_oauth_token}
          token -> {:ok, token}
        end

      {:error, reason} ->
        {:error, {:claude_oauth_token_read, reason}}
    end
  end

  defp read_oauth_token(_account), do: {:error, :missing_claude_oauth_token}

  defp maybe_put_timeout(opts, timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0, do: Keyword.put(opts, :timeout_ms, timeout_ms)
  defp maybe_put_timeout(opts, _timeout_ms), do: opts

  defp quota_snapshot(%Config{} = config, %Lease{} = lease, rate_limits) when is_map(rate_limits) do
    {limit, remaining} = quota_limit_remaining(rate_limits)

    Snapshot.new(%{
      provider_kind: config.kind,
      credential_ref_summary: lease.credential_ref_summary,
      account_id_summary: lease.account_id,
      status: quota_status(rate_limits),
      remaining: remaining,
      limit: limit,
      reset_at: quota_reset_at(rate_limits),
      details: %{"rate_limits" => rate_limits}
    })
  end

  defp quota_limit_remaining(rate_limits) do
    bucket = Map.get(rate_limits, "session") || Map.get(rate_limits, :session) || Map.get(rate_limits, "primary") || Map.get(rate_limits, :primary) || %{}
    {integer_value(Map.get(bucket, "limit") || Map.get(bucket, :limit)), integer_value(Map.get(bucket, "remaining") || Map.get(bucket, :remaining))}
  end

  defp quota_status(rate_limits) do
    buckets =
      [
        Map.get(rate_limits, "session") || Map.get(rate_limits, :session),
        Map.get(rate_limits, "weekly") || Map.get(rate_limits, :weekly),
        Map.get(rate_limits, "primary") || Map.get(rate_limits, :primary),
        Map.get(rate_limits, "secondary") || Map.get(rate_limits, :secondary)
      ]
      |> Enum.filter(&is_map/1)

    cond do
      Enum.any?(buckets, &quota_exhausted?/1) -> :exhausted
      Enum.any?(buckets, &quota_limited?/1) -> :limited
      buckets == [] -> :unknown
      true -> :healthy
    end
  end

  defp quota_exhausted?(bucket) do
    (Map.get(bucket, "status") || Map.get(bucket, :status)) in ["rate_limited", "exhausted"] or
      integer_value(Map.get(bucket, "remaining") || Map.get(bucket, :remaining)) == 0
  end

  defp quota_limited?(bucket) do
    limit = integer_value(Map.get(bucket, "limit") || Map.get(bucket, :limit))
    remaining = integer_value(Map.get(bucket, "remaining") || Map.get(bucket, :remaining))
    limit > 0 and remaining > 0 and remaining / limit < 0.1
  end

  defp quota_reset_at(rate_limits) do
    [
      Map.get(rate_limits, "session") || Map.get(rate_limits, :session),
      Map.get(rate_limits, "weekly") || Map.get(rate_limits, :weekly)
    ]
    |> Enum.filter(&is_map/1)
    |> Enum.flat_map(fn bucket ->
      [Map.get(bucket, "reset_at") || Map.get(bucket, :reset_at)]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
    |> List.first()
    |> parse_datetime()
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} -> timestamp
      _error -> nil
    end
  end

  defp integer_value(value) when is_integer(value) and value >= 0, do: value
  defp integer_value(_value), do: 0
end
