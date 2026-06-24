defmodule SymphonyElixir.Agent.ExecutionPlan.Record.Plan do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Record.Context
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Extensions
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Item
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Rendering
  alias SymphonyElixir.Agent.ExecutionPlan.Record.SourcePlanRef

  @type t :: %__MODULE__{
          schema: String.t(),
          plan_id: String.t(),
          context: Context.t(),
          status: String.t(),
          items: [Item.t()],
          source_plan_ref: SourcePlanRef.t() | nil,
          rendering: Rendering.t() | nil,
          extensions: Extensions.t() | nil,
          created_at: String.t(),
          updated_at: String.t(),
          revision: pos_integer()
        }

  defstruct schema: nil,
            plan_id: nil,
            context: nil,
            status: nil,
            items: [],
            source_plan_ref: nil,
            rendering: nil,
            extensions: nil,
            created_at: nil,
            updated_at: nil,
            revision: nil
end
