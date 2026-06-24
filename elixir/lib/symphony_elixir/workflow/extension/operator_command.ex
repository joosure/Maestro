defmodule SymphonyElixir.Workflow.Extension.OperatorCommand do
  @moduledoc """
  Behaviour for operator commands contributed by workflow extensions.

  Operator commands are an extension-owned business surface exposed through a
  platform dispatcher. Platform CLI and Mix entrypoints should dispatch by
  command id instead of invoking concrete extension modules directly.
  """

  @type command_id :: String.t()
  @type result :: {String.t(), String.t(), non_neg_integer()}

  @callback id() :: command_id()
  @callback evaluate([String.t()], keyword()) :: result()
end
