defmodule SymphonyElixir.Agent.ExecutionPlan.ErrorCodes do
  @moduledoc """
  Namespace for Agent execution-plan machine-code contracts.

  Error codes are grouped by the boundary that owns them. Runtime modules should
  depend on these submodules instead of repeating machine-code strings or
  nesting error-code contracts under unrelated runtime modules.
  """
end
