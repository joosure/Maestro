defmodule SymphonyWorkerDaemon.Api.Health do
  @moduledoc false

  alias SymphonyWorkerDaemon.Api.{RateLimit, Response}
  alias SymphonyWorkerDaemon.BridgeProxy.UpstreamPolicy
  alias SymphonyWorkerDaemon.{CapacityManager, CommandPolicy, Protocol}
  alias SymphonyWorkerDaemon.Protocol.{Features, HealthStatus}
  alias SymphonyWorkerDaemon.Protocol.Fields, as: ProtocolFields
  alias SymphonyWorkerDaemon.Session

  @status_key ProtocolFields.status()
  @protocol_version_key ProtocolFields.protocol_version()
  @daemon_version_key ProtocolFields.daemon_version()
  @worker_id_key ProtocolFields.worker_id()
  @daemon_instance_id_key ProtocolFields.daemon_instance_id()
  @worker_profile_version_key ProtocolFields.worker_profile_version()
  @capacity_key ProtocolFields.capacity()
  @session_ledger_key ProtocolFields.session_ledger()
  @rate_limits_key ProtocolFields.rate_limits()
  @features_key ProtocolFields.features()
  @capabilities_key ProtocolFields.capabilities()

  @spec payload(keyword()) :: map()
  def payload(opts) when is_list(opts) do
    capacity = safe_capacity_status(Keyword.get(opts, :capacity_manager, CapacityManager))
    ledger_health = safe_ledger_health(Keyword.get(opts, :session_ledger))

    %{
      @status_key => aggregate_status(capacity, ledger_health),
      @protocol_version_key => Protocol.protocol_version(),
      @daemon_version_key => Keyword.get(opts, :daemon_version, Protocol.daemon_version()),
      @worker_id_key => Keyword.get(opts, :worker_id),
      @daemon_instance_id_key => Keyword.get(opts, :daemon_instance_id),
      @worker_profile_version_key => Keyword.get(opts, :worker_profile_version, "default"),
      @capacity_key => Response.stringify_map(capacity),
      @session_ledger_key => Response.stringify_map(ledger_health),
      @rate_limits_key => RateLimit.health(opts),
      @features_key => features(opts),
      @capabilities_key => CommandPolicy.capabilities(command_policy_opts(opts))
    }
  end

  @spec features(keyword()) :: [String.t()]
  def features(opts) when is_list(opts) do
    case Keyword.get(opts, :features, Protocol.supported_features()) do
      features when is_list(features) -> features
      _features -> Protocol.supported_features()
    end
    |> Enum.map(&to_string/1)
    |> maybe_remove_dynamic_tool_bridge_feature(opts)
  end

  defp maybe_remove_dynamic_tool_bridge_feature(features, opts) do
    if dynamic_tool_bridge_proxy_available?(opts) do
      features
    else
      List.delete(features, Features.dynamic_tool_bridge_proxy())
    end
  end

  defp dynamic_tool_bridge_proxy_available?(opts) when is_list(opts) do
    Keyword.get(opts, :enable_dynamic_tool_bridge_proxy?, false) and
      match?(
        {:ok, [_first | _rest]},
        UpstreamPolicy.prepare_allowed_upstreams(Keyword.get(opts, :allowed_dynamic_tool_bridge_upstreams, []))
      )
  end

  defp command_policy_opts(opts) do
    [
      allowed_executables: Keyword.get(opts, :allowed_executables, []),
      allow_any_executable?: Keyword.get(opts, :allow_any_executable?, false),
      allow_shell?: Keyword.get(opts, :allow_shell?, false)
    ]
  end

  defp safe_capacity_status(capacity_manager) do
    CapacityManager.status(capacity_manager)
  catch
    :exit, _reason -> %{status: HealthStatus.unavailable()}
  end

  defp safe_ledger_health(session_ledger) do
    Session.Ledger.health(session_ledger)
  catch
    :exit, _reason -> %{status: HealthStatus.unavailable(), persistence: :unknown}
  end

  defp aggregate_status(capacity, ledger_health)
       when is_map(capacity) and is_map(ledger_health) do
    capacity_status = Map.get(capacity, :status, HealthStatus.ready())
    ledger_status = Map.get(ledger_health, :status, HealthStatus.ready())

    HealthStatus.aggregate(capacity_status, ledger_status)
  end
end
