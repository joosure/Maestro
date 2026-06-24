defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Runtime.Input do
  @moduledoc """
  Extension-owned runtime input for Coding PR Delivery reconciliation.

  This struct is the only runtime shape consumed by Coding PR Delivery business
  rules. It is built at the runtime adapter boundary from the platform
  `Workflow.Extension.Runtime.Projection` so reconciliation code does not depend
  on platform runtime envelope internals.
  """

  alias SymphonyElixir.Workflow.Extension.Runtime.Context, as: RuntimeContext
  alias SymphonyElixir.Workflow.Extension.Runtime.Projection, as: RuntimeProjection

  defstruct running_issue_ids: MapSet.new(),
            claimed_issue_ids: MapSet.new(),
            running_count: 0,
            claimed_count: 0,
            available_slots: nil,
            max_concurrent_agents: nil,
            extension_state: %{}

  @type t :: %__MODULE__{
          running_issue_ids: term(),
          claimed_issue_ids: term(),
          running_count: non_neg_integer(),
          claimed_count: non_neg_integer(),
          available_slots: non_neg_integer() | nil,
          max_concurrent_agents: non_neg_integer() | nil,
          extension_state: map()
        }

  @spec from_context(RuntimeContext.t(), String.t()) :: t()
  def from_context(%RuntimeContext{runtime: %RuntimeProjection{} = projection}, extension_id)
      when is_binary(extension_id) do
    from_projection(projection, extension_id)
  end

  @spec from_projection(RuntimeProjection.t(), String.t()) :: t()
  def from_projection(%RuntimeProjection{} = projection, extension_id) when is_binary(extension_id) do
    %__MODULE__{
      running_issue_ids: projection.running_issue_ids,
      claimed_issue_ids: projection.claimed_issue_ids,
      running_count: projection.running_count,
      claimed_count: projection.claimed_count,
      available_slots: projection.available_slots,
      max_concurrent_agents: projection.max_concurrent_agents,
      extension_state: RuntimeProjection.extension_state(projection, extension_id)
    }
  end

  @spec running_issue?(t(), term()) :: boolean()
  def running_issue?(%__MODULE__{} = input, issue_id) when is_binary(issue_id) do
    MapSet.member?(input.running_issue_ids, issue_id)
  end

  def running_issue?(%__MODULE__{}, _issue_id), do: false

  @spec claimed_issue?(t(), term()) :: boolean()
  def claimed_issue?(%__MODULE__{} = input, issue_id) when is_binary(issue_id) do
    MapSet.member?(input.claimed_issue_ids, issue_id)
  end

  def claimed_issue?(%__MODULE__{}, _issue_id), do: false
end
