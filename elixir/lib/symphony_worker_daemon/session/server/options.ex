defmodule SymphonyWorkerDaemon.Session.Server.Options do
  @moduledoc false

  @default_line_bytes 1_048_576

  @spec runner(keyword()) :: keyword()
  def runner(opts) when is_list(opts) do
    opts
    |> Keyword.get(:process_runner_opts, [])
    |> Keyword.merge(
      allow_shell?: Keyword.get(opts, :allow_shell?, false),
      line: Keyword.get(opts, :line) || @default_line_bytes
    )
  end

  @spec command_policy(keyword()) :: keyword()
  def command_policy(opts) when is_list(opts) do
    [
      allowed_executables: Keyword.get(opts, :allowed_executables, []),
      allow_any_executable?: Keyword.get(opts, :allow_any_executable?, false),
      allow_shell?: Keyword.get(opts, :allow_shell?, false)
    ]
  end

  @spec bridge_proxy(keyword()) :: keyword()
  def bridge_proxy(opts) when is_list(opts) do
    [
      bridge_proxy_requester: Keyword.get(opts, :bridge_proxy_requester),
      bridge_proxy_timeout_ms: Keyword.get(opts, :bridge_proxy_timeout_ms),
      bridge_proxy_port: Keyword.get(opts, :bridge_proxy_port),
      session_token: Keyword.get(opts, :dynamic_tool_bridge_session_token),
      enable_dynamic_tool_bridge_proxy?: Keyword.get(opts, :enable_dynamic_tool_bridge_proxy?, false),
      allowed_dynamic_tool_bridge_upstreams: Keyword.get(opts, :allowed_dynamic_tool_bridge_upstreams, []),
      allow_private_dynamic_tool_bridge_upstreams?: Keyword.get(opts, :allow_private_dynamic_tool_bridge_upstreams?, false),
      max_header_bytes: Keyword.get(opts, :max_header_bytes),
      max_request_body_bytes: Keyword.get(opts, :max_request_body_bytes)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end
end
