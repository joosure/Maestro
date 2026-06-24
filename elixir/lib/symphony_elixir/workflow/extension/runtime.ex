defmodule SymphonyElixir.Workflow.Extension.Runtime do
  @moduledoc """
  Runtime facade for registered workflow extensions.

  Platform callers use this module instead of invoking concrete workflow
  business contexts directly. Runtime implementation details live under
  `Workflow.Extension.Runtime.*` modules so this facade stays stable.
  """

  alias SymphonyElixir.Workflow.Extension.Runtime.Context, as: RuntimeContext
  alias SymphonyElixir.Workflow.Extension.Runtime.Dispatcher

  @type runtime_state :: map()
  @type extension_opts :: SymphonyElixir.Workflow.Extension.Runtime.Options.extension_opts()

  @spec run_poll_cycle(RuntimeContext.t(), runtime_state(), keyword()) ::
          {:ok, runtime_state()} | {:error, map()}
  def run_poll_cycle(%RuntimeContext{} = context, runtime_state, opts \\ [])
      when is_map(runtime_state) and is_list(opts) do
    Dispatcher.run_poll_cycle(context, runtime_state, opts)
  end
end
