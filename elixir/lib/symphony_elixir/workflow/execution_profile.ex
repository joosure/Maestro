defmodule SymphonyElixir.Workflow.ExecutionProfile do
  @moduledoc """
  Behaviour for runtime execution-profile handlers.

  The registry controls which handlers are admitted at boot. Repository
  `WORKFLOW.md` files may select an admitted execution profile by name, but they
  cannot define or load handler modules.
  """

  @type action :: atom()
  @type capability :: String.t()

  @callback supported_actions() :: [action()]
  @callback required_capabilities() :: [capability()]
  @callback run(map()) :: {:ok, term()} | {:error, term()}
end
