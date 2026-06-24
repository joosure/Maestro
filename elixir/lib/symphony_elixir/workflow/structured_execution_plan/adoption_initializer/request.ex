defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.Request do
  @moduledoc """
  Stable internal request for workflow structured-plan adoption initialization.

  External settings, issue maps, and runtime opts are normalized into this
  struct before the initializer runs. Downstream initializer code should consume
  this struct instead of raw maps.
  """

  @enforce_keys [
    :enabled?,
    :registry_profile_config,
    :issue_context,
    :run_context,
    :tracker_context,
    :store_opts
  ]

  defstruct [
    :enabled?,
    :registry_profile_config,
    :issue_context,
    :run_context,
    :tracker_context,
    :store_opts
  ]

  @type issue_context :: %{
          issue_id: term(),
          issue_identifier: term()
        }

  @type run_context :: %{
          plan_id: term(),
          run_id: term(),
          route_key: term(),
          status: term(),
          created_at: term(),
          updated_at: term()
        }

  @type tracker_context :: %{
          tracker_kind: term()
        }

  @type t :: %__MODULE__{
          enabled?: boolean(),
          registry_profile_config: map(),
          issue_context: issue_context(),
          run_context: run_context(),
          tracker_context: tracker_context(),
          store_opts: keyword()
        }
end
