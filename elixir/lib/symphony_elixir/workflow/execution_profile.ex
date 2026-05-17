defmodule SymphonyElixir.Workflow.ExecutionProfile do
  @moduledoc """
  Behaviour for boot-registered execution-profile descriptors.

  The registry controls which handlers are admitted at boot. Repository
  `WORKFLOW.md` files may select only execution-profile names declared by the
  active workflow profile; a matching registry entry can provide action scope
  and required capability metadata, but cannot make an undeclared name
  selectable. Registry runtime handlers must declare this behaviour explicitly;
  matching the callback names by duck typing is not a supported extension
  contract.
  """

  @type action :: atom()
  @type capability :: String.t()

  @callback supported_actions() :: [action()]
  @callback required_capabilities() :: [capability()]
end
