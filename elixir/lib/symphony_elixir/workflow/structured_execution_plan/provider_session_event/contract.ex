defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Contract do
  @moduledoc """
  Canonical provider-session event contract.

  Provider-native tasks and hooks are normalized into this event shape before
  workflow storage or validation code consumes them. Raw provider payload aliases
  belong in `ProviderSessionEvent.RawInput`, not here.
  """

  @schema_id "workflow.execution_plan.provider_session_event.v1"
  @extension_key "symphony.provider_session_events"

  @schema_key "schema"
  @authority_key "authority"
  @trust_class_key "trust_class"
  @provider_kind_key "provider_kind"
  @surface_key "surface"
  @event_id_key "event_id"
  @run_id_key "run_id"
  @observed_at_key "observed_at"
  @tasks_key "tasks"
  @hook_observation_key "hook_observation"
  @warnings_key "warnings"
  @extensions_key "extensions"

  @provider_task_id_key "provider_task_id"
  @title_key "title"
  @requested_status_key "requested_status"
  @note_key "note"
  @correlation_key "correlation"
  @provider_position_key "provider_position"
  @provider_surface_key "provider_surface"

  @hook_name_key "hook_name"
  @phase_key "phase"
  @status_key "status"
  @summary_key "summary"

  @allowed_event_keys [
    @schema_key,
    @authority_key,
    @trust_class_key,
    @provider_kind_key,
    @surface_key,
    @event_id_key,
    @run_id_key,
    @observed_at_key,
    @tasks_key,
    @hook_observation_key,
    @warnings_key,
    @extensions_key
  ]
  @required_event_keys [
    @schema_key,
    @authority_key,
    @trust_class_key,
    @provider_kind_key,
    @surface_key,
    @event_id_key,
    @observed_at_key
  ]
  @allowed_task_keys [@provider_task_id_key, @title_key, @requested_status_key, @note_key, @correlation_key]
  @allowed_hook_keys [@hook_name_key, @phase_key, @status_key, @summary_key]

  @spec schema_id() :: String.t()
  def schema_id, do: @schema_id

  @spec extension_key() :: String.t()
  def extension_key, do: @extension_key

  @spec schema_key() :: String.t()
  def schema_key, do: @schema_key

  @spec authority_key() :: String.t()
  def authority_key, do: @authority_key

  @spec trust_class_key() :: String.t()
  def trust_class_key, do: @trust_class_key

  @spec provider_kind_key() :: String.t()
  def provider_kind_key, do: @provider_kind_key

  @spec surface_key() :: String.t()
  def surface_key, do: @surface_key

  @spec event_id_key() :: String.t()
  def event_id_key, do: @event_id_key

  @spec run_id_key() :: String.t()
  def run_id_key, do: @run_id_key

  @spec observed_at_key() :: String.t()
  def observed_at_key, do: @observed_at_key

  @spec tasks_key() :: String.t()
  def tasks_key, do: @tasks_key

  @spec hook_observation_key() :: String.t()
  def hook_observation_key, do: @hook_observation_key

  @spec warnings_key() :: String.t()
  def warnings_key, do: @warnings_key

  @spec extensions_key() :: String.t()
  def extensions_key, do: @extensions_key

  @spec provider_task_id_key() :: String.t()
  def provider_task_id_key, do: @provider_task_id_key

  @spec title_key() :: String.t()
  def title_key, do: @title_key

  @spec requested_status_key() :: String.t()
  def requested_status_key, do: @requested_status_key

  @spec note_key() :: String.t()
  def note_key, do: @note_key

  @spec correlation_key() :: String.t()
  def correlation_key, do: @correlation_key

  @spec provider_position_key() :: String.t()
  def provider_position_key, do: @provider_position_key

  @spec provider_surface_key() :: String.t()
  def provider_surface_key, do: @provider_surface_key

  @spec hook_name_key() :: String.t()
  def hook_name_key, do: @hook_name_key

  @spec phase_key() :: String.t()
  def phase_key, do: @phase_key

  @spec status_key() :: String.t()
  def status_key, do: @status_key

  @spec summary_key() :: String.t()
  def summary_key, do: @summary_key

  @spec allowed_event_keys() :: [String.t()]
  def allowed_event_keys, do: @allowed_event_keys

  @spec required_event_keys() :: [String.t()]
  def required_event_keys, do: @required_event_keys

  @spec allowed_task_keys() :: [String.t()]
  def allowed_task_keys, do: @allowed_task_keys

  @spec allowed_hook_keys() :: [String.t()]
  def allowed_hook_keys, do: @allowed_hook_keys
end
