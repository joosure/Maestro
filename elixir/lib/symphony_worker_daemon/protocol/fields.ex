defmodule SymphonyWorkerDaemon.Protocol.Fields do
  @moduledoc """
  Stable JSON field names for the Worker Daemon HTTP protocol.

  These keys are shared by the daemon server and the main application client.
  Keep request, response, and query-field names here so protocol evolution has
  one owner.
  """

  @protocol_version "protocol_version"
  @request_id "request_id"
  @session_id "session_id"
  @run_id "run_id"
  @caller "caller"
  @command "command"
  @workspace "workspace"
  @env "env"
  @resource_budget "resource_budget"
  @timeout_policy "timeout_policy"
  @required_features "required_features"
  @dynamic_tool_bridge "dynamic_tool_bridge"
  @provider_kind "provider_kind"
  @worker_pool "worker_pool"
  @owner "owner"
  @tenant_id "tenant_id"
  @deployment_id "deployment_id"
  @mode "mode"
  @argv "argv"
  @cwd "cwd"
  @workspace_path "workspace_path"
  @remote_workspace_path "remote_workspace_path"
  @workspace_root "workspace_root"
  @startup_timeout_ms "startup_timeout_ms"
  @idle_timeout_ms "idle_timeout_ms"
  @session_timeout_ms "session_timeout_ms"
  @output_buffer_bytes "output_buffer_bytes"
  @output_buffer_limit "output_buffer_limit"
  @max_output_bytes "max_output_bytes"
  @type_field "type"
  @transport "transport"
  @symphony_base_url "symphony_base_url"
  @base_path "base_path"
  @execute_path "execute_path"
  @token "token"
  @provider_env "provider_env"
  @input "input"
  @encoding "encoding"
  @idempotency_key "idempotency_key"
  @reason "reason"
  @status "status"
  @daemon_version "daemon_version"
  @daemon_software_version "daemon_software_version"
  @worker_id "worker_id"
  @daemon_instance_id "daemon_instance_id"
  @worker_profile_version "worker_profile_version"
  @capacity "capacity"
  @session_ledger "session_ledger"
  @rate_limits "rate_limits"
  @features "features"
  @capabilities "capabilities"
  @metadata "metadata"
  @sessions "sessions"
  @events "events"
  @event_id "event_id"
  @stream "stream"
  @data "data"
  @timestamp_ms "timestamp_ms"
  @lease_id "lease_id"
  @os_pid "os_pid"
  @exit_status "exit_status"
  @started_at_ms "started_at_ms"
  @updated_at_ms "updated_at_ms"
  @after_event_id "after_event_id"
  @limit "limit"
  @code "code"
  @message "message"
  @retryable "retryable"
  @retryable_question "retryable?"
  @details "details"

  @create_request_keys [
    @protocol_version,
    @request_id,
    @session_id,
    @run_id,
    @caller,
    @command,
    @workspace,
    @env,
    @resource_budget,
    @timeout_policy,
    @required_features,
    @dynamic_tool_bridge
  ]
  @caller_keys [@provider_kind, @worker_pool, @owner, @tenant_id, @deployment_id]
  @command_keys [@mode, @argv, @command]
  @workspace_keys [@cwd, @workspace_path, @remote_workspace_path, @workspace_root]
  @timeout_policy_keys [@startup_timeout_ms, @idle_timeout_ms, @session_timeout_ms]
  @resource_budget_keys [@output_buffer_bytes, @output_buffer_limit, @max_output_bytes]
  @dynamic_tool_bridge_keys [
    @type_field,
    @transport,
    @symphony_base_url,
    @base_path,
    @execute_path,
    @token,
    @provider_env
  ]
  @input_request_keys [@protocol_version, @request_id, @input, @encoding]
  @stop_request_keys [@protocol_version, @request_id, @idempotency_key, @reason]
  @cleanup_request_keys [@protocol_version, @request_id, @idempotency_key]
  @session_filter_keys [@owner, @tenant_id, @run_id, @status]
  @event_filter_keys [@after_event_id, @limit]
  @safe_error_keys [@code, @message, @retryable, @retryable_question, @details]

  @spec protocol_version() :: String.t()
  def protocol_version, do: @protocol_version

  @spec request_id() :: String.t()
  def request_id, do: @request_id

  @spec session_id() :: String.t()
  def session_id, do: @session_id

  @spec run_id() :: String.t()
  def run_id, do: @run_id

  @spec caller() :: String.t()
  def caller, do: @caller

  @spec command() :: String.t()
  def command, do: @command

  @spec workspace() :: String.t()
  def workspace, do: @workspace

  @spec env() :: String.t()
  def env, do: @env

  @spec resource_budget() :: String.t()
  def resource_budget, do: @resource_budget

  @spec timeout_policy() :: String.t()
  def timeout_policy, do: @timeout_policy

  @spec required_features() :: String.t()
  def required_features, do: @required_features

  @spec dynamic_tool_bridge() :: String.t()
  def dynamic_tool_bridge, do: @dynamic_tool_bridge

  @spec provider_kind() :: String.t()
  def provider_kind, do: @provider_kind

  @spec worker_pool() :: String.t()
  def worker_pool, do: @worker_pool

  @spec owner() :: String.t()
  def owner, do: @owner

  @spec tenant_id() :: String.t()
  def tenant_id, do: @tenant_id

  @spec deployment_id() :: String.t()
  def deployment_id, do: @deployment_id

  @spec mode() :: String.t()
  def mode, do: @mode

  @spec argv() :: String.t()
  def argv, do: @argv

  @spec cwd() :: String.t()
  def cwd, do: @cwd

  @spec workspace_path() :: String.t()
  def workspace_path, do: @workspace_path

  @spec remote_workspace_path() :: String.t()
  def remote_workspace_path, do: @remote_workspace_path

  @spec workspace_root() :: String.t()
  def workspace_root, do: @workspace_root

  @spec startup_timeout_ms() :: String.t()
  def startup_timeout_ms, do: @startup_timeout_ms

  @spec idle_timeout_ms() :: String.t()
  def idle_timeout_ms, do: @idle_timeout_ms

  @spec session_timeout_ms() :: String.t()
  def session_timeout_ms, do: @session_timeout_ms

  @spec output_buffer_bytes() :: String.t()
  def output_buffer_bytes, do: @output_buffer_bytes

  @spec output_buffer_limit() :: String.t()
  def output_buffer_limit, do: @output_buffer_limit

  @spec max_output_bytes() :: String.t()
  def max_output_bytes, do: @max_output_bytes

  @spec type() :: String.t()
  def type, do: @type_field

  @spec transport() :: String.t()
  def transport, do: @transport

  @spec symphony_base_url() :: String.t()
  def symphony_base_url, do: @symphony_base_url

  @spec base_path() :: String.t()
  def base_path, do: @base_path

  @spec execute_path() :: String.t()
  def execute_path, do: @execute_path

  @spec token() :: String.t()
  def token, do: @token

  @spec provider_env() :: String.t()
  def provider_env, do: @provider_env

  @spec input() :: String.t()
  def input, do: @input

  @spec encoding() :: String.t()
  def encoding, do: @encoding

  @spec idempotency_key() :: String.t()
  def idempotency_key, do: @idempotency_key

  @spec reason() :: String.t()
  def reason, do: @reason

  @spec status() :: String.t()
  def status, do: @status

  @spec daemon_version() :: String.t()
  def daemon_version, do: @daemon_version

  @spec daemon_software_version() :: String.t()
  def daemon_software_version, do: @daemon_software_version

  @spec worker_id() :: String.t()
  def worker_id, do: @worker_id

  @spec daemon_instance_id() :: String.t()
  def daemon_instance_id, do: @daemon_instance_id

  @spec worker_profile_version() :: String.t()
  def worker_profile_version, do: @worker_profile_version

  @spec capacity() :: String.t()
  def capacity, do: @capacity

  @spec session_ledger() :: String.t()
  def session_ledger, do: @session_ledger

  @spec rate_limits() :: String.t()
  def rate_limits, do: @rate_limits

  @spec features() :: String.t()
  def features, do: @features

  @spec capabilities() :: String.t()
  def capabilities, do: @capabilities

  @spec metadata() :: String.t()
  def metadata, do: @metadata

  @spec sessions() :: String.t()
  def sessions, do: @sessions

  @spec events() :: String.t()
  def events, do: @events

  @spec event_id() :: String.t()
  def event_id, do: @event_id

  @spec stream() :: String.t()
  def stream, do: @stream

  @spec data() :: String.t()
  def data, do: @data

  @spec timestamp_ms() :: String.t()
  def timestamp_ms, do: @timestamp_ms

  @spec lease_id() :: String.t()
  def lease_id, do: @lease_id

  @spec os_pid() :: String.t()
  def os_pid, do: @os_pid

  @spec exit_status() :: String.t()
  def exit_status, do: @exit_status

  @spec started_at_ms() :: String.t()
  def started_at_ms, do: @started_at_ms

  @spec updated_at_ms() :: String.t()
  def updated_at_ms, do: @updated_at_ms

  @spec after_event_id() :: String.t()
  def after_event_id, do: @after_event_id

  @spec limit() :: String.t()
  def limit, do: @limit

  @spec code() :: String.t()
  def code, do: @code

  @spec message() :: String.t()
  def message, do: @message

  @spec retryable() :: String.t()
  def retryable, do: @retryable

  @spec retryable_question() :: String.t()
  def retryable_question, do: @retryable_question

  @spec details() :: String.t()
  def details, do: @details

  @spec create_request_keys() :: [String.t()]
  def create_request_keys, do: @create_request_keys

  @spec caller_keys() :: [String.t()]
  def caller_keys, do: @caller_keys

  @spec command_keys() :: [String.t()]
  def command_keys, do: @command_keys

  @spec workspace_keys() :: [String.t()]
  def workspace_keys, do: @workspace_keys

  @spec timeout_policy_keys() :: [String.t()]
  def timeout_policy_keys, do: @timeout_policy_keys

  @spec resource_budget_keys() :: [String.t()]
  def resource_budget_keys, do: @resource_budget_keys

  @spec dynamic_tool_bridge_keys() :: [String.t()]
  def dynamic_tool_bridge_keys, do: @dynamic_tool_bridge_keys

  @spec input_request_keys() :: [String.t()]
  def input_request_keys, do: @input_request_keys

  @spec stop_request_keys() :: [String.t()]
  def stop_request_keys, do: @stop_request_keys

  @spec cleanup_request_keys() :: [String.t()]
  def cleanup_request_keys, do: @cleanup_request_keys

  @spec session_filter_keys() :: [String.t()]
  def session_filter_keys, do: @session_filter_keys

  @spec event_filter_keys() :: [String.t()]
  def event_filter_keys, do: @event_filter_keys

  @spec safe_error_keys() :: [String.t()]
  def safe_error_keys, do: @safe_error_keys
end
