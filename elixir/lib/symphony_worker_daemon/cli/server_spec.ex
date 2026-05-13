defmodule SymphonyWorkerDaemon.CLI.ServerSpec do
  @moduledoc false

  @spec children(keyword()) :: [{module(), keyword()}]
  def children(opts) when is_list(opts) do
    resources = resources(opts)
    [daemon_child(opts, resources), api_child(opts, resources)]
  end

  defp resources(opts) do
    %{
      registry: Keyword.get(opts, :registry, SymphonyWorkerDaemon.SessionRegistry),
      capacity_manager: Keyword.get(opts, :capacity_manager, SymphonyWorkerDaemon.CapacityManager),
      rate_limiter: Keyword.get(opts, :rate_limiter, SymphonyWorkerDaemon.RateLimiter),
      session_ledger: Keyword.get(opts, :session_ledger, SymphonyWorkerDaemon.Session.Ledger),
      session_supervisor: Keyword.get(opts, :session_supervisor, SymphonyWorkerDaemon.Session.Supervisor),
      daemon_supervisor: Keyword.get(opts, :daemon_supervisor_name, SymphonyWorkerDaemon.Supervisor)
    }
  end

  defp daemon_child(opts, resources) do
    {SymphonyWorkerDaemon.Application,
     [
       name: Map.fetch!(resources, :daemon_supervisor),
       registry: Map.fetch!(resources, :registry),
       capacity_manager: Map.fetch!(resources, :capacity_manager),
       rate_limiter: Map.fetch!(resources, :rate_limiter),
       session_ledger: Map.fetch!(resources, :session_ledger),
       session_ledger_path: Keyword.get(opts, :session_ledger_path),
       session_supervisor: Map.fetch!(resources, :session_supervisor),
       workspace_roots: Keyword.fetch!(opts, :workspace_roots),
       max_sessions: Keyword.fetch!(opts, :max_sessions),
       max_sessions_per_tenant: Keyword.get(opts, :max_sessions_per_tenant)
     ]}
  end

  defp api_child(opts, resources) do
    {Bandit,
     [
       plug: {SymphonyWorkerDaemon.Api, api_opts(opts, resources)},
       scheme: :http,
       ip: Keyword.fetch!(opts, :ip),
       port: Keyword.fetch!(opts, :port)
     ]}
  end

  defp api_opts(opts, resources) do
    [
      token: Keyword.get(opts, :token),
      allow_unauthenticated?: Keyword.get(opts, :allow_unauthenticated?, false),
      api_clients: Keyword.get(opts, :api_clients),
      owner: Keyword.get(opts, :owner),
      tenant_id: Keyword.get(opts, :tenant_id),
      roles: Keyword.get(opts, :roles, []),
      session_ledger: Map.fetch!(resources, :session_ledger),
      rate_limiter: Map.fetch!(resources, :rate_limiter),
      registry: Map.fetch!(resources, :registry),
      capacity_manager: Map.fetch!(resources, :capacity_manager),
      session_supervisor: Map.fetch!(resources, :session_supervisor),
      workspace_roots: Keyword.fetch!(opts, :workspace_roots),
      worker_id: Keyword.fetch!(opts, :worker_id),
      daemon_instance_id: Keyword.fetch!(opts, :daemon_instance_id),
      worker_profile_version: Keyword.fetch!(opts, :worker_profile_version),
      allow_shell?: Keyword.get(opts, :allow_shell?, false),
      allowed_executables: Keyword.fetch!(opts, :allowed_executables),
      allow_any_executable?: Keyword.get(opts, :allow_any_executable?, false),
      max_sessions_per_tenant: Keyword.get(opts, :max_sessions_per_tenant),
      rate_limit_window_ms: Keyword.fetch!(opts, :rate_limit_window_ms),
      unauthenticated_rate_limit: Keyword.fetch!(opts, :unauthenticated_rate_limit),
      api_rate_limit: Keyword.fetch!(opts, :api_rate_limit),
      session_create_rate_limit: Keyword.fetch!(opts, :session_create_rate_limit),
      enable_dynamic_tool_bridge_proxy?: Keyword.get(opts, :enable_dynamic_tool_bridge_proxy?, false),
      allowed_dynamic_tool_bridge_upstreams: Keyword.get(opts, :allowed_dynamic_tool_bridge_upstreams, []),
      allow_private_dynamic_tool_bridge_upstreams?: Keyword.get(opts, :allow_private_dynamic_tool_bridge_upstreams?, false)
    ]
  end
end
