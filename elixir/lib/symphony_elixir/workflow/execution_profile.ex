defmodule SymphonyElixir.Workflow.ExecutionProfile do
  @moduledoc """
  Behaviour for runtime execution-profile handlers.

  The registry controls which handlers are admitted at boot. Repository
  `WORKFLOW.md` files may select only execution-profile names declared by the
  active workflow profile; a matching registry entry can provide the runtime
  handler, but cannot make an undeclared name selectable.
  """

  @type action :: atom()
  @type capability :: String.t()

  @callback supported_actions() :: [action()]
  @callback required_capabilities() :: [capability()]
  @callback run(map()) :: {:ok, term()} | {:error, term()}
end
