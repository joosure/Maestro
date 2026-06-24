defmodule SymphonyElixir.Workflow.Extension do
  @moduledoc """
  Behaviour for workflow runtime extensions.

  Runtime extensions are the current pre-plugin boundary: platform code invokes
  this contract, while concrete built-in extensions own workflow business rules.
  A future plugin system can change how extension modules are discovered without
  changing the orchestrator's runtime call shape.
  """

  alias SymphonyElixir.Workflow.Extension.Runtime.Context, as: RuntimeContext
  alias SymphonyElixir.Workflow.Extension.Runtime.Result, as: RuntimeResult

  @type extension_id :: String.t()

  @callback id() :: extension_id()

  @callback run_poll_cycle(RuntimeContext.t(), keyword()) ::
              {:ok, RuntimeResult.t()} | {:error, term()}

  @callback validate_settings(map(), term()) :: :ok | {:error, term()}

  @optional_callbacks validate_settings: 2
end
