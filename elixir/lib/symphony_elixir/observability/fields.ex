defmodule SymphonyElixir.Observability.Fields do
  @moduledoc false

  @context_metadata_fields ~w[
    request_id
    correlation_id
    run_id
    issue_id
    issue_identifier
    tracker_kind
    agent_provider_kind
    provider_kind
    session_id
    thread_id
    turn_id
    turn_number
    max_turns
    attempt
    worker_host
    workspace_path
    failure_class
    error_code
    operation
    retryable
  ]a

  @message_context_fields ~w[
    request_id
    correlation_id
    run_id
    issue_id
    issue_identifier
    session_id
    thread_id
    turn_id
    turn_number
    max_turns
    tracker_kind
    agent_provider_kind
    provider_kind
    worker_host
    workspace_path
    failure_class
    error_code
    operation
    retryable
    retry_delay_ms
    route_key
    target_route
    target_state
    workflow_profile
    workflow_profile_version
    workflow_route_key
    workflow_transition_target_route_key
    source_workflow_profile
    source_workflow_profile_version
    source_workflow_route_key
    source_route_refs
    target_workflow_profile
    target_workflow_profile_version
    target_workflow_route_key
    workflow_route_action
    workflow_gate_status
    workflow_gate
    workflow_gate_reason
    workflow_missing_capabilities
    tool_name
    dynamic_tool_exposure
    dynamic_tool_count
    dynamic_tool_names
    dynamic_tool_rejection_reason
    hook_name
    stream_label
    workflow_path
    workflow_hash
    prompt_hash
    prompt_length
    http_method
    http_path
    status
    duration_ms
    current_state
    previous_state
    policy_action
    candidate_count
    running_count
    claimed_count
    available_slots
    max_concurrent_agents
    skip_reason
    operation_name
    repo_provider_runtime
    retry_count
    exit_code
    sink_name
    handler_id
    file_path
    log_format
  ]

  @metadata_fields ~w[
    timestamp
    event
    component
    service
    request_id
    correlation_id
    run_id
    issue_id
    issue_identifier
    tracker_kind
    agent_provider_kind
    provider_kind
    session_id
    thread_id
    turn_id
    turn_number
    max_turns
    attempt
    worker_host
    workspace_path
    failure_class
    error_code
    operation
    retryable
    stateful
    session_type
    retry_delay_ms
    route_key
    target_route
    target_state
    workflow_profile
    workflow_profile_version
    workflow_route_key
    workflow_transition_target_route_key
    source_workflow_profile
    source_workflow_profile_version
    source_workflow_route_key
    source_route_refs
    target_workflow_profile
    target_workflow_profile_version
    target_workflow_route_key
    workflow_route_action
    workflow_gate_status
    workflow_gate
    workflow_gate_reason
    workflow_missing_capabilities
    tool_name
    dynamic_tool_usage_kind
    dynamic_tool_workflow_capability
    dynamic_tool_side_effect
    dynamic_tool_source_kind
    dynamic_tool_schema_version
    dynamic_tool_deprecated
    dynamic_tool_operator_only
    dynamic_tool_exposure
    dynamic_tool_count
    dynamic_tool_names
    dynamic_tool_fallback_reason
    dynamic_tool_fallback_ambiguous
    dynamic_tool_failure_reason
    dynamic_tool_rejection_reason
    dynamic_tool_provider_capability_unavailable_count
    dynamic_tool_provider_capability_unavailable
    hook_name
    stream_label
    skip_reason
    workflow_path
    workflow_hash
    prompt_hash
    prompt_length
    http_method
    http_path
    status
    duration_ms
    error
    error_stack
    payload_summary
    result_summary
    current_state
    previous_state
    policy_action
    candidate_count
    running_count
    claimed_count
    available_slots
    max_concurrent_agents
    operation_name
    repo_provider_runtime
    retry_count
    exit_code
    sink_name
    handler_id
    file_path
    log_format
  ]a

  @generic_metadata_fields @metadata_fields -- [:timestamp, :service]

  @spec context_metadata_fields() :: [atom()]
  def context_metadata_fields, do: @context_metadata_fields

  @spec generic_metadata_fields() :: [atom()]
  def generic_metadata_fields, do: @generic_metadata_fields

  @spec message_context_fields() :: [String.t()]
  def message_context_fields, do: @message_context_fields

  @spec metadata_fields() :: [atom()]
  def metadata_fields, do: @metadata_fields
end
