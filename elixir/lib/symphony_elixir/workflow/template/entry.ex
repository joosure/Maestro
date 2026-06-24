defmodule SymphonyElixir.Workflow.Template.Entry do
  @moduledoc """
  Public workflow-template entry record contributed by platform templates or extensions.

  The struct is the stable data contract returned by template contributors.
  `Workflow.Template` owns construction and validation; `Workflow.Template.Registry`
  owns lookup and aggregation.
  """

  @enforce_keys [
    :template_alias,
    :asset_root,
    :asset_path,
    :profile_kind,
    :profile_version,
    :tracker_kind,
    :repo_provider_kind,
    :agent_provider_kind
  ]
  defstruct [
    :template_alias,
    :asset_root,
    :asset_path,
    :profile_kind,
    :profile_version,
    :tracker_kind,
    :repo_provider_kind,
    :agent_provider_kind,
    :credential_ref
  ]

  @type t :: %__MODULE__{
          template_alias: String.t(),
          asset_root: Path.t(),
          asset_path: Path.t(),
          profile_kind: String.t(),
          profile_version: pos_integer(),
          tracker_kind: String.t(),
          repo_provider_kind: String.t(),
          agent_provider_kind: String.t(),
          credential_ref: String.t() | nil
        }
end
