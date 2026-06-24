defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Supervision do
  @moduledoc """
  Runtime children contributed by the Coding PR Delivery extension.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Supervision.{ChildSpecs, Options}

  @spec children(term()) :: [Supervisor.child_spec()]
  def children(opts) do
    case Options.normalize(opts) do
      {:ok, options} -> ChildSpecs.children(options)
      {:error, reason} -> [ChildSpecs.failing_child(reason)]
    end
  end
end
