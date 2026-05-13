defmodule SymphonyWorkerDaemon.Api.SessionOptions do
  @moduledoc false

  alias SymphonyWorkerDaemon.CapacityManager

  @spec build(keyword()) :: keyword()
  def build(opts) when is_list(opts) do
    [
      registry: Keyword.get(opts, :registry, SymphonyWorkerDaemon.SessionRegistry),
      capacity_manager: Keyword.get(opts, :capacity_manager, CapacityManager),
      session_ledger: Keyword.get(opts, :session_ledger),
      workspace_roots: Keyword.get(opts, :workspace_roots, []),
      worker_id: Keyword.get(opts, :worker_id),
      daemon_instance_id: Keyword.get(opts, :daemon_instance_id),
      allow_shell?: Keyword.get(opts, :allow_shell?, false),
      allowed_executables: Keyword.get(opts, :allowed_executables, []),
      allow_any_executable?: Keyword.get(opts, :allow_any_executable?, false),
      max_sessions_per_tenant: Keyword.get(opts, :max_sessions_per_tenant),
      line: Keyword.get(opts, :line),
      bridge_proxy_requester: Keyword.get(opts, :bridge_proxy_requester),
      bridge_proxy_timeout_ms: Keyword.get(opts, :bridge_proxy_timeout_ms),
      bridge_proxy_port: Keyword.get(opts, :bridge_proxy_port),
      dynamic_tool_bridge_session_token: Keyword.get(opts, :dynamic_tool_bridge_session_token),
      enable_dynamic_tool_bridge_proxy?: Keyword.get(opts, :enable_dynamic_tool_bridge_proxy?, false),
      allowed_dynamic_tool_bridge_upstreams: Keyword.get(opts, :allowed_dynamic_tool_bridge_upstreams, []),
      allow_private_dynamic_tool_bridge_upstreams?: Keyword.get(opts, :allow_private_dynamic_tool_bridge_upstreams?, false),
      max_header_bytes: Keyword.get(opts, :max_header_bytes),
      max_request_body_bytes: Keyword.get(opts, :max_request_body_bytes),
      output_buffer_limit: Keyword.get(opts, :output_buffer_limit)
    ]
  end
end
