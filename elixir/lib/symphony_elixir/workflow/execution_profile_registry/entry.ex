defmodule SymphonyElixir.Workflow.ExecutionProfileRegistry.Entry do
  @moduledoc false

  @enforce_keys [
    :name,
    :profile_kind,
    :profile_versions,
    :supported_actions,
    :required_capabilities,
    :runtime_handler
  ]
  defstruct [
    :name,
    :profile_kind,
    :profile_versions,
    :supported_actions,
    :required_capabilities,
    :runtime_handler
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          profile_kind: String.t(),
          profile_versions: [pos_integer()],
          supported_actions: [atom()],
          required_capabilities: [String.t()],
          runtime_handler: module()
        }
end
