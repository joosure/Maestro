defmodule SymphonyElixir.Agent.Runtime do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.Target
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.{Endpoint, PoolResolver, RuntimeEnv}
  alias SymphonyElixir.Config, as: RuntimeConfig
  alias SymphonyElixir.Config.Schema, as: RuntimeSchema
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @type worker_runtime_info :: %{
          optional(:agent_process_pid) => String.t() | nil,
          optional(:agent_provider_kind) => String.t(),
          optional(:run_id) => String.t(),
          optional(:worker_host) => String.t() | nil,
          optional(:workspace_path) => Path.t() | nil,
          optional(:worker_daemon_endpoint) => String.t() | nil,
          optional(:worker_daemon_endpoint_id) => String.t() | nil,
          optional(:worker_daemon_worker_id) => String.t() | nil,
          optional(:worker_daemon_daemon_instance_id) => String.t() | nil,
          optional(:issue) => SymphonyElixir.Issue.t(),
          optional(:issue_fact_source) => atom(),
          optional(:monotonic_ms) => integer(),
          optional(:failure_class) => String.t() | nil,
          optional(:error) => String.t()
        }

  @spec resolve_target(Path.t(), keyword()) :: {:ok, Target.t()} | {:error, term()}
  def resolve_target(workspace, opts \\ []) when is_binary(workspace) and is_list(opts) do
    opts = effective_runtime_opts(opts)

    target =
      Target.new(%{
        placement: Keyword.get(opts, :agent_runtime_placement),
        worker_pool: Keyword.get(opts, :worker_pool),
        worker_host: Keyword.get(opts, :worker_host),
        workspace_path: workspace,
        remote_workspace_path: Keyword.get(opts, :remote_workspace_path),
        env: Keyword.get(opts, :agent_runtime_env, %{}),
        metadata: target_metadata(opts)
      })

    with {:ok, target} <- maybe_resolve_worker_daemon_endpoint(target, opts),
         {:ok, target} <- validate_target(target) do
      emit_worker_selected(target, opts)
      {:ok, target}
    end
  end

  @spec provider_runtime_context(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def provider_runtime_context(workspace, opts \\ []) when is_binary(workspace) and is_list(opts) do
    with {:ok, settings} <- runtime_settings(opts),
         runtime_opts <- opts |> Keyword.put(:settings, settings) |> effective_runtime_opts(),
         {:ok, target} <- resolve_target(workspace, runtime_opts),
         {:ok, turn_sandbox_policy} <-
           RuntimeSchema.resolve_runtime_turn_sandbox_policy(
             settings,
             workspace,
             remote: Target.remote?(target)
           ) do
      {:ok,
       target
       |> Target.to_context()
       |> Map.merge(%{
         workspace_root: settings.workspace.root,
         hook_timeout_ms: settings.hooks.timeout_ms,
         executor_opts: executor_opts(runtime_opts),
         turn_sandbox_policy: turn_sandbox_policy
       })}
    end
  end

  defp runtime_settings(opts) do
    case Keyword.get(opts, :settings) do
      %RuntimeSchema{} = settings -> {:ok, settings}
      _ -> RuntimeConfig.settings()
    end
  end

  defp effective_runtime_opts(opts) when is_list(opts) do
    opts
    |> Keyword.get(:settings)
    |> case do
      %RuntimeSchema{} = settings -> settings |> settings_runtime_opts() |> Keyword.merge(opts)
      _settings -> opts
    end
  end

  defp settings_runtime_opts(%RuntimeSchema{runtime: runtime}) when is_map(runtime) do
    runtime_agent = map_value(runtime, :agent)
    worker_daemon = map_value(runtime_agent, :worker_daemon)

    [
      agent_runtime_placement: map_value(runtime_agent, :placement),
      worker_pool: map_value(runtime_agent, :worker_pool),
      worker_host: map_value(runtime_agent, :worker_host),
      remote_workspace_path: map_value(runtime_agent, :remote_workspace_path),
      agent_runtime_env: map_value(runtime_agent, :env),
      worker_daemon_endpoint: map_value(worker_daemon, :endpoint),
      worker_daemon_endpoints: map_value(worker_daemon, :endpoints),
      worker_daemon_pools: map_value(worker_daemon, :pools),
      worker_daemon_token: worker_daemon_token(worker_daemon),
      worker_daemon_timeout_ms: map_value(worker_daemon, :timeout_ms),
      worker_daemon_required_features: map_value(worker_daemon, :required_features),
      worker_daemon_health_cache_ttl_ms: map_value(worker_daemon, :health_cache_ttl_ms),
      worker_daemon_circuit_ttl_ms: map_value(worker_daemon, :circuit_ttl_ms)
    ]
    |> Enum.reject(fn {_key, value} -> runtime_option_empty?(value) end)
  end

  defp settings_runtime_opts(_settings), do: []

  defp worker_daemon_token(worker_daemon) when is_map(worker_daemon) do
    case map_value(worker_daemon, :token_env) |> normalize_optional_string() do
      token_env when is_binary(token_env) -> System.get_env(token_env) |> normalize_optional_string()
      nil -> nil
    end
  end

  defp worker_daemon_token(_worker_daemon), do: nil

  defp runtime_option_empty?(nil), do: true
  defp runtime_option_empty?([]), do: true
  defp runtime_option_empty?(map) when is_map(map), do: map_size(map) == 0
  defp runtime_option_empty?(_value), do: false

  defp executor_opts(opts) when is_list(opts) do
    [
      :worker_daemon_token,
      :worker_daemon_timeout_ms,
      :worker_daemon_required_features,
      :worker_daemon_accepted_health_statuses,
      :worker_daemon_preflight?,
      :worker_daemon_endpoint,
      :worker_daemon_endpoints,
      :worker_daemon_pools,
      :worker_daemon_worker_id,
      :worker_daemon_health_cache_ttl_ms,
      :worker_daemon_circuit_ttl_ms,
      :worker_daemon_endpoint_state?,
      :worker_daemon_requester,
      :worker_daemon_client
    ]
    |> Enum.reduce([], fn key, acc ->
      case Keyword.fetch(opts, key) do
        {:ok, value} when not is_nil(value) -> Keyword.put(acc, key, value)
        _missing_or_nil -> acc
      end
    end)
    |> Enum.reverse()
  end

  defp validate_target(%Target{placement: :ssh, worker_host: nil} = target) do
    {:error,
     {:agent_runtime_target_invalid, :missing_worker_host,
      %{
        worker_placement: Atom.to_string(target.placement),
        worker_pool: target.worker_pool,
        workspace_path: target.workspace_path
      }}}
  end

  defp validate_target(%Target{placement: :worker_daemon} = target) do
    case target.metadata |> map_value(:worker_daemon_endpoint) |> Endpoint.normalize_validated() do
      {:ok, endpoint} ->
        {:ok, %Target{target | metadata: Map.put(target.metadata, :worker_daemon_endpoint, endpoint)}}

      {:error, :worker_daemon_endpoint_missing} ->
        {:error,
         {:agent_runtime_target_invalid, :missing_worker_daemon_endpoint,
          %{
            worker_placement: Atom.to_string(target.placement),
            worker_pool: target.worker_pool,
            workspace_path: target.workspace_path
          }}}

      {:error, reason} ->
        {:error,
         {:agent_runtime_target_invalid, :invalid_worker_daemon_endpoint,
          %{
            worker_placement: Atom.to_string(target.placement),
            worker_pool: target.worker_pool,
            workspace_path: target.workspace_path,
            reason: reason
          }}}
    end
  end

  defp validate_target(%Target{placement: :unsupported} = target) do
    {:error,
     {:agent_runtime_target_invalid, :unsupported_placement,
      %{
        worker_placement: Atom.to_string(target.placement),
        worker_pool: target.worker_pool,
        worker_host: target.worker_host,
        workspace_path: target.workspace_path
      }}}
  end

  defp validate_target(%Target{} = target), do: {:ok, target}

  defp maybe_resolve_worker_daemon_endpoint(%Target{placement: :worker_daemon} = target, opts) do
    case map_value(target.metadata, :worker_daemon_endpoint) |> normalize_optional_string() do
      endpoint when is_binary(endpoint) ->
        {:ok, target}

      nil ->
        case PoolResolver.resolve(target, opts) do
          {:ok, selection} -> {:ok, apply_worker_daemon_selection(target, selection)}
          {:error, :worker_daemon_endpoint_missing} -> {:ok, target}
          {:error, {:worker_daemon_pool_unavailable, failures}} -> worker_daemon_pool_error(target, failures)
          {:error, reason} -> worker_daemon_pool_error(target, [%{reason: inspect(reason, limit: 20, printable_limit: 1_000)}])
        end
    end
  end

  defp maybe_resolve_worker_daemon_endpoint(%Target{} = target, _opts), do: {:ok, target}

  defp apply_worker_daemon_selection(%Target{} = target, selection) when is_map(selection) do
    metadata =
      target.metadata
      |> Map.put(:worker_daemon_endpoint, Map.fetch!(selection, :endpoint))
      |> maybe_put(:worker_daemon_worker_id, Map.get(selection, :worker_id))
      |> maybe_put(:worker_daemon_daemon_instance_id, Map.get(selection, :daemon_instance_id))
      |> maybe_put(:worker_daemon_endpoint_id, Map.get(selection, :endpoint_id))
      |> maybe_put(:worker_daemon_endpoint_source, Map.get(selection, :source))
      |> maybe_put(:worker_daemon_health_source, Map.get(selection, :health_source))
      |> maybe_put(:worker_daemon_health, Map.get(selection, :health))

    %Target{target | metadata: metadata}
  end

  defp worker_daemon_pool_error(%Target{} = target, failures) when is_list(failures) do
    {:error,
     {:agent_runtime_target_invalid, :worker_daemon_pool_unavailable,
      %{
        worker_placement: Atom.to_string(target.placement),
        worker_pool: target.worker_pool,
        workspace_path: target.workspace_path,
        failures: failures
      }}}
  end

  defp target_metadata(opts) do
    %{
      run_id: Keyword.get(opts, :run_id),
      issue_id: Keyword.get(opts, :issue_id) || map_value(Keyword.get(opts, :issue), :id),
      issue_identifier: Keyword.get(opts, :issue_identifier) || map_value(Keyword.get(opts, :issue), :identifier),
      agent_provider_kind: Keyword.get(opts, :agent_provider_kind),
      worker_daemon_endpoint: worker_daemon_endpoint(opts),
      worker_daemon_worker_id: normalize_optional_string(Keyword.get(opts, :worker_daemon_worker_id))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp emit_worker_selected(%Target{} = target, opts) do
    ObsLogger.emit(
      :info,
      :agent_worker_selected,
      %{
        component: "agent_runtime",
        operation: "resolve_target",
        status: "selected",
        run_id: Keyword.get(opts, :run_id),
        correlation_id: Keyword.get(opts, :run_id),
        issue_id: Keyword.get(opts, :issue_id) || map_value(Keyword.get(opts, :issue), :id),
        issue_identifier: Keyword.get(opts, :issue_identifier) || map_value(Keyword.get(opts, :issue), :identifier),
        agent_provider_kind: Keyword.get(opts, :agent_provider_kind),
        workspace_path: target.workspace_path,
        worker_placement: Atom.to_string(target.placement),
        worker_pool: target.worker_pool,
        worker_host: target.worker_host,
        worker_daemon_endpoint: target.metadata |> map_value(:worker_daemon_endpoint) |> Endpoint.safe(),
        worker_daemon_worker_id: map_value(target.metadata, :worker_daemon_worker_id),
        worker_daemon_endpoint_id: map_value(target.metadata, :worker_daemon_endpoint_id)
      }
    )
  end

  defp worker_daemon_endpoint(opts) do
    Keyword.get(opts, :worker_daemon_endpoint)
    |> normalize_optional_string()
    |> case do
      endpoint when is_binary(endpoint) ->
        endpoint

      nil ->
        Application.get_env(:symphony_elixir, :worker_daemon_endpoint)
        |> normalize_optional_string()
        |> case do
          endpoint when is_binary(endpoint) -> endpoint
          nil -> RuntimeEnv.endpoint()
        end
    end
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  defp normalize_optional_string(_value), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp map_value(nil, _key), do: nil
  defp map_value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp map_value(_value, _key), do: nil
end
