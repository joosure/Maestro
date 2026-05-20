defmodule SymphonyElixir.Workflow.Readiness do
  @moduledoc """
  Public facade for workflow readiness facts and gate rendering.

  The implementation lives in `SymphonyElixir.Workflow.Readiness.Facts`; callers
  should keep depending on this module unless they are extending the readiness
  internals.
  """

  alias SymphonyElixir.Workflow.Readiness.Facts
  alias SymphonyElixir.Workflow.RouteFacts

  @spec facts(map(), keyword() | map()) :: map()
  defdelegate facts(issue, opts \\ []), to: Facts

  @spec gate(RouteFacts.t() | nil, map()) :: map()
  defdelegate gate(route_facts, capabilities), to: Facts
end
