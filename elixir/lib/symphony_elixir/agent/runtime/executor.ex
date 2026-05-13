defmodule SymphonyElixir.Agent.Runtime.Executor do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, Target}

  @type execution_handle :: term()

  @callback start(CommandSpec.t(), Target.t(), keyword()) ::
              {:ok, execution_handle()} | {:error, term()}
  @callback stop(execution_handle(), keyword()) :: :ok | {:error, term()}
  @callback alive?(execution_handle()) :: boolean()
end
