defmodule SymphonyWorkerDaemon.CLI.Arguments do
  @moduledoc false

  @switches [
    host: :string,
    port: :integer,
    token: :string,
    token_env: :string,
    allow_unauthenticated: :boolean,
    owner: :string,
    tenant_id: :string,
    session_ledger_path: :string,
    worker_id: :string,
    daemon_instance_id: :string,
    worker_profile_version: :string,
    workspace_root: :string,
    max_sessions: :integer,
    max_sessions_per_tenant: :integer,
    rate_limit_window_ms: :integer,
    unauthenticated_rate_limit: :integer,
    api_rate_limit: :integer,
    session_create_rate_limit: :integer,
    allow_shell: :boolean,
    allow_executable: :string,
    allow_any_executable: :boolean,
    enable_dynamic_tool_bridge_proxy: :boolean,
    allow_dynamic_tool_bridge_upstream: :string,
    allow_private_dynamic_tool_bridge_upstream: :boolean
  ]

  @spec parse([String.t()]) :: {:ok, keyword()} | {:error, String.t()}
  def parse(args) when is_list(args) do
    case OptionParser.parse(args, strict: @switches) do
      {opts, [], []} ->
        {:ok, opts}

      {_opts, _args, invalid} when invalid != [] ->
        {:error, "Invalid worker daemon option: #{inspect(invalid)}\n\n" <> usage_message()}

      _result ->
        {:error, usage_message()}
    end
  end

  @spec usage_message() :: String.t()
  def usage_message do
    """
    Usage:
      symphony worker-daemon --workspace-root <path> [--host 127.0.0.1] [--port 4001] [--token-env SYMPHONY_WORKER_DAEMON_TOKEN]

    Options:
      --workspace-root <path>       Allowed worker-local workspace root. May be repeated.
      --allow-executable <command>  Allowed provider/helper executable. May be repeated.
      --allow-any-executable        Disable executable allowlist for isolated local development only.
      --enable-dynamic-tool-bridge-proxy
                                    Enable the session-scoped Dynamic Tool bridge proxy.
      --allow-dynamic-tool-bridge-upstream <url>
                                    Allowed Dynamic Tool bridge upstream base URL. May be repeated.
      --allow-private-dynamic-tool-bridge-upstream
                                    Allow loopback/private bridge upstream addresses for explicitly allowlisted local deployments.
      --host <ip|localhost>         Listen address. Defaults to 127.0.0.1.
      --port <port>                 Listen port. Defaults to 4001.
      --token <token>               Bearer token for Symphony client authentication.
      --token-env <VAR>             Read the bearer token from VAR.
      --allow-unauthenticated       Disable daemon API authentication for isolated local development only.
      --owner <owner>               Owner identity for the single-token daemon client. Defaults to symphony.
      --tenant-id <id>              Optional tenant identity for the single-token daemon client.
      --session-ledger-path <path>  Optional JSON ledger for terminal/lost session recovery.
      --worker-id <id>              Stable worker identity. Defaults to the host name.
      --daemon-instance-id <id>     Ephemeral daemon process identity. Defaults to a UUID.
      --worker-profile-version <v>  Worker profile version exposed by daemon health.
      --max-sessions <count>        Maximum concurrent provider sessions. Defaults to 1.
      --max-sessions-per-tenant <count>
                                    Maximum concurrent sessions per tenant/owner.
      --rate-limit-window-ms <ms>   Fixed rate-limit window. Defaults to 60000.
      --unauthenticated-rate-limit <count>
                                    Failed-auth requests per source IP per window. Defaults to 120.
      --api-rate-limit <count>      Authenticated requests per tenant/owner per window. Defaults to 600.
      --session-create-rate-limit <count>
                                    Session creates per tenant/owner per window. Defaults to 60.
      --allow-shell                 Enable shell command mode for trusted worker profiles.
    """
    |> String.trim()
  end
end
