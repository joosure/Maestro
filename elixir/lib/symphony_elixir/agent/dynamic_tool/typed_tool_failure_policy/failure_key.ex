defmodule SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.FailureKey do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.FailureScope

  defstruct scope: nil,
            error_code: nil

  @type t :: %__MODULE__{
          scope: FailureScope.t(),
          error_code: String.t()
        }

  @spec new(FailureScope.t(), String.t()) :: {:ok, t()} | :error
  def new(%FailureScope{} = scope, error_code) when is_binary(error_code) do
    case String.trim(error_code) do
      "" -> :error
      error_code -> {:ok, %__MODULE__{scope: scope, error_code: error_code}}
    end
  end

  def new(_scope, _error_code), do: :error
end
