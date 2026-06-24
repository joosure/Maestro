defmodule SymphonyElixir.Workflow.Extension.CompletionValidator do
  @moduledoc """
  Behaviour for extension-owned completion evidence validators.
  """

  @type validation_result :: %{required(String.t()) => term()}

  @callback profile_kind() :: String.t()
  @callback validate(map(), keyword() | map()) :: validation_result()
  @callback merge_gate(map(), map()) :: validation_result()
end
