defmodule SymphonyWorkerDaemon.Api.Health do
  @moduledoc false

  alias SymphonyWorkerDaemon.Api.{RateLimit, Response}
  alias SymphonyWorkerDaemon.BridgeProxy.UpstreamPolicy
  alias SymphonyWorkerDaemon.{CapacityManager, CommandPolicy, Protocol}
  alias SymphonyWorkerDaemon.Session

  @spec payload(keyword()) :: map()
  def payload(opts) when is_list(opts) do
    capacity = safe_capacity_status(Keyword.get(opts, :capacity_manager, CapacityManager))
    ledger_health = safe_ledger_health(Keyword.get(opts, :session_ledger))

    %{
      "status" => aggregate_status(capacity, ledger_health),
      "protocol_version" => Protocol.protocol_version(),
      "daemon_version" => Keyword.get(opts, :daemon_version, Protocol.daemon_version()),
      "worker_id" => Keyword.get(opts, :worker_id),
      "daemon_instance_id" => Keyword.get(opts, :daemon_instance_id),
      "worker_profile_version" => Keyword.get(opts, :worker_profile_version, "default"),
      "capacity" => Response.stringify_map(capacity),
      "session_ledger" => Response.stringify_map(ledger_health),
      "rate_limits" => RateLimit.health(opts),
      "features" => features(opts),
      "capabilities" => CommandPolicy.capabilities(command_policy_opts(opts))
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
      List.delete(features, "dynamic_tool_bridge_proxy")
    end
  end

  defp dynamic_tool_bridge_proxy_available?(opts) when is_list(opts) do
    Keyword.get(opts, :enable_dynamic_tool_bridge_proxy?, false) and
      match?({:ok, [_first | _rest]}, UpstreamPolicy.prepare_allowed_upstreams(Keyword.get(opts, :allowed_dynamic_tool_bridge_upstreams, [])))
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
    :exit, _reason -> %{status: :unavailable}
  end

  defp safe_ledger_health(session_ledger) do
    Session.Ledger.health(session_ledger)
  catch
    :exit, _reason -> %{status: :unavailable, persistence: :unknown}
  end

  defp aggregate_status(capacity, ledger_health) when is_map(capacity) and is_map(ledger_health) do
    capacity_status = capacity |> Map.get(:status, :ready) |> to_string()
    ledger_status = ledger_health |> Map.get(:status, :ready) |> to_string()

    cond do
      capacity_status == "unavailable" or ledger_status == "unavailable" -> "unavailable"
      ledger_status == "degraded" -> "degraded"
      true -> capacity_status
    end
  end
end
