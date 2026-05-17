defmodule SymphonyWorkerDaemon.Config do
  @moduledoc false

  alias SymphonyWorkerDaemon.Auth.Defaults, as: AuthDefaults
  alias SymphonyWorkerDaemon.Config.{Authentication, ListenAddress, Options, Policies, WorkerIdentity, WorkspaceRoots}

  @default_host "127.0.0.1"
  @default_port 4001
  @default_max_sessions 1
  @default_rate_limit_window_ms 60_000
  @default_unauthenticated_rate_limit 120
  @default_api_rate_limit 600
  @default_session_create_rate_limit 60
  @default_token_env "SYMPHONY_WORKER_DAEMON_TOKEN"
  @default_owner AuthDefaults.default_owner()
  @default_worker_profile_version "default"

  @type deps :: %{
          dir?: (String.t() -> boolean()),
          canonicalize: (String.t() -> {:ok, String.t()} | {:error, term()}),
          getenv: (String.t() -> String.t() | nil),
          hostname: (-> {:ok, String.t()} | {:error, term()}),
          uuid: (-> String.t())
        }

  @type t :: %__MODULE__{
          host: String.t(),
          ip: :inet.ip_address(),
          port: non_neg_integer(),
          token: String.t() | nil,
          owner: String.t(),
          tenant_id: String.t() | nil,
          session_ledger_path: Path.t() | nil,
          worker_id: String.t(),
          daemon_instance_id: String.t(),
          worker_profile_version: String.t(),
          workspace_roots: [String.t()],
          max_sessions: pos_integer(),
          max_sessions_per_tenant: pos_integer() | nil,
          rate_limit_window_ms: pos_integer(),
          unauthenticated_rate_limit: pos_integer(),
          api_rate_limit: pos_integer(),
          session_create_rate_limit: pos_integer(),
          allow_shell?: boolean(),
          allowed_executables: [map()],
          allow_any_executable?: boolean(),
          allow_unauthenticated?: boolean(),
          enable_dynamic_tool_bridge_proxy?: boolean(),
          allowed_dynamic_tool_bridge_upstreams: [String.t()],
          allow_private_dynamic_tool_bridge_upstreams?: boolean()
        }

  defstruct host: @default_host,
            ip: {127, 0, 0, 1},
            port: @default_port,
            token: nil,
            owner: @default_owner,
            tenant_id: nil,
            session_ledger_path: nil,
            worker_id: nil,
            daemon_instance_id: nil,
            worker_profile_version: @default_worker_profile_version,
            workspace_roots: [],
            max_sessions: @default_max_sessions,
            max_sessions_per_tenant: nil,
            rate_limit_window_ms: @default_rate_limit_window_ms,
            unauthenticated_rate_limit: @default_unauthenticated_rate_limit,
            api_rate_limit: @default_api_rate_limit,
            session_create_rate_limit: @default_session_create_rate_limit,
            allow_shell?: false,
            allowed_executables: [],
            allow_any_executable?: false,
            allow_unauthenticated?: false,
            enable_dynamic_tool_bridge_proxy?: false,
            allowed_dynamic_tool_bridge_upstreams: [],
            allow_private_dynamic_tool_bridge_upstreams?: false

  @spec normalize_cli_options(keyword(), deps()) :: {:ok, t()} | {:error, String.t()}
  def normalize_cli_options(opts, deps) when is_list(opts) and is_map(deps) do
    with {:ok, host, ip} <- ListenAddress.resolve(opts, @default_host),
         {:ok, port} <- Options.integer(opts, :port, @default_port, 0, 65_535),
         {:ok, token, allow_unauthenticated?} <- Authentication.resolve(opts, deps, @default_token_env),
         {:ok, owner} <- Options.required_string(opts, :owner, @default_owner, "owner"),
         {:ok, worker_id} <- WorkerIdentity.resolve(opts, deps),
         {:ok, daemon_instance_id} <- Options.required_string(opts, :daemon_instance_id, deps.uuid.(), "daemon instance id"),
         {:ok, workspace_roots} <- WorkspaceRoots.resolve(opts, deps),
         {:ok, max_sessions} <- Options.integer(opts, :max_sessions, @default_max_sessions, 1, 1_000_000),
         {:ok, max_sessions_per_tenant} <- Options.optional_integer(opts, :max_sessions_per_tenant, 1, 1_000_000),
         {:ok, rate_limit_window_ms} <- Options.integer(opts, :rate_limit_window_ms, @default_rate_limit_window_ms, 1, 86_400_000),
         {:ok, unauthenticated_rate_limit} <- Options.integer(opts, :unauthenticated_rate_limit, @default_unauthenticated_rate_limit, 1, 1_000_000),
         {:ok, api_rate_limit} <- Options.integer(opts, :api_rate_limit, @default_api_rate_limit, 1, 10_000_000),
         {:ok, session_create_rate_limit} <- Options.integer(opts, :session_create_rate_limit, @default_session_create_rate_limit, 1, 1_000_000),
         {:ok, executable_policy} <- Policies.executable(opts),
         {:ok, dynamic_tool_bridge_policy} <- Policies.dynamic_tool_bridge(opts) do
      {:ok,
       %__MODULE__{
         host: host,
         ip: ip,
         port: port,
         token: token,
         owner: owner,
         tenant_id: opts |> Options.last_value(:tenant_id) |> Options.normalize_optional_string(),
         session_ledger_path: opts |> Options.last_value(:session_ledger_path) |> Options.normalize_optional_string() |> Options.maybe_expand_path(),
         worker_id: worker_id,
         daemon_instance_id: daemon_instance_id,
         worker_profile_version: opts |> Options.last_value(:worker_profile_version) |> Options.normalize_optional_string() || @default_worker_profile_version,
         workspace_roots: workspace_roots,
         max_sessions: max_sessions,
         max_sessions_per_tenant: max_sessions_per_tenant,
         rate_limit_window_ms: rate_limit_window_ms,
         unauthenticated_rate_limit: unauthenticated_rate_limit,
         api_rate_limit: api_rate_limit,
         session_create_rate_limit: session_create_rate_limit,
         allow_shell?: Keyword.get(opts, :allow_shell, false),
         allowed_executables: Map.fetch!(executable_policy, :allowed_executables),
         allow_any_executable?: Map.fetch!(executable_policy, :allow_any_executable?),
         allow_unauthenticated?: allow_unauthenticated?,
         enable_dynamic_tool_bridge_proxy?: Map.fetch!(dynamic_tool_bridge_policy, :enable_dynamic_tool_bridge_proxy?),
         allowed_dynamic_tool_bridge_upstreams: Map.fetch!(dynamic_tool_bridge_policy, :allowed_dynamic_tool_bridge_upstreams),
         allow_private_dynamic_tool_bridge_upstreams?: Map.fetch!(dynamic_tool_bridge_policy, :allow_private_dynamic_tool_bridge_upstreams?)
       }}
    end
  end

  @spec to_server_opts(t()) :: keyword()
  def to_server_opts(%__MODULE__{} = config) do
    [
      host: config.host,
      ip: config.ip,
      port: config.port,
      token: config.token,
      owner: config.owner,
      tenant_id: config.tenant_id,
      session_ledger_path: config.session_ledger_path,
      worker_id: config.worker_id,
      daemon_instance_id: config.daemon_instance_id,
      worker_profile_version: config.worker_profile_version,
      workspace_roots: config.workspace_roots,
      max_sessions: config.max_sessions,
      max_sessions_per_tenant: config.max_sessions_per_tenant,
      rate_limit_window_ms: config.rate_limit_window_ms,
      unauthenticated_rate_limit: config.unauthenticated_rate_limit,
      api_rate_limit: config.api_rate_limit,
      session_create_rate_limit: config.session_create_rate_limit,
      allow_shell?: config.allow_shell?,
      allowed_executables: config.allowed_executables,
      allow_any_executable?: config.allow_any_executable?,
      allow_unauthenticated?: config.allow_unauthenticated?,
      enable_dynamic_tool_bridge_proxy?: config.enable_dynamic_tool_bridge_proxy?,
      allowed_dynamic_tool_bridge_upstreams: config.allowed_dynamic_tool_bridge_upstreams,
      allow_private_dynamic_tool_bridge_upstreams?: config.allow_private_dynamic_tool_bridge_upstreams?
    ]
  end
end
