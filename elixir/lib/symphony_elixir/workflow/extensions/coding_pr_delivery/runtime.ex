defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Runtime do
  @moduledoc """
  Runtime adapter for the Coding PR Delivery extension.

  The adapter translates platform `RuntimeContext` input into the
  extension-owned reconciliation service and returns a platform `RuntimeResult`.
  """

  alias SymphonyElixir.Workflow.Extension.Runtime.Context, as: RuntimeContext
  alias SymphonyElixir.Workflow.Extension.Runtime.Result, as: RuntimeResult
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.RuntimeDefaults, as: Defaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Runtime.{Input, Options}

  @spec run_poll_cycle(RuntimeContext.t(), keyword()) :: {:ok, RuntimeResult.t()} | {:error, term()}
  def run_poll_cycle(%RuntimeContext{} = context, opts) do
    with {:ok, reconciler_opts} <- Options.reconciler_opts(opts) do
      input = Input.from_context(context, CodingPrDelivery.id())

      reconciler_opts =
        reconciler_opts
        |> Defaults.reconciler_opts()
        |> Keyword.put_new(:workflow_scope, context.workflow_scope)

      result = Reconciliation.reconcile_runtime(context.settings, input, reconciler_opts)

      RuntimeResult.replace_extension_state(result.extension_state, commands: result.commands)
    end
  end
end
