defmodule SymphonyElixir.Agent.DynamicTool.ExecutionGuard.Decision do
  @moduledoc false

  @enforce_keys [:code, :message]
  defstruct code: nil,
            message: nil,
            details: %{}

  @type t :: %__MODULE__{
          code: String.t(),
          message: String.t(),
          details: map()
        }

  @spec reject(String.t(), String.t(), map()) :: t()
  def reject(code, message, details \\ %{}) when is_binary(code) and is_binary(message) and is_map(details) do
    %__MODULE__{code: code, message: message, details: details}
  end
end
