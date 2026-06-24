defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Readiness.StructuredPlanReaderStoreBackend do
  @moduledoc """
  Bundled structured-plan reader backend backed by the platform canonical store.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.Context
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store

  @behaviour SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.Plan.Reader

  @impl true
  def fetch_plan(context, config, reader_opts) do
    case Context.option_value(config, :plan_id) do
      plan_id when is_binary(plan_id) ->
        Store.fetch(plan_id, reader_opts)

      _plan_id ->
        with {:ok, run_id} <- Context.required(context, :run_id),
             {:ok, profile} <- Context.required(context, :workflow_profile),
             {:ok, route_key} <- Context.required(context, :route_key) do
          Store.active_plan(run_id, profile, route_key, reader_opts)
        end
    end
  end
end
