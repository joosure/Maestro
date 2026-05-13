defmodule SymphonyElixir.AgentProvider.Error do
  @moduledoc """
  Provider-neutral error shape for expected agent-provider failures.
  """

  @type t :: %__MODULE__{
          provider: String.t() | nil,
          operation: atom() | nil,
          code: atom() | nil,
          message: String.t(),
          retryable?: boolean(),
          details: map()
        }

  defstruct provider: nil,
            operation: nil,
            code: nil,
            message: "",
            retryable?: false,
            details: %{}

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      provider: Map.get(attrs, :provider) || Map.get(attrs, "provider"),
      operation: normalize_atom(Map.get(attrs, :operation) || Map.get(attrs, "operation")),
      code: normalize_atom(Map.get(attrs, :code) || Map.get(attrs, "code")),
      message: normalize_message(Map.get(attrs, :message) || Map.get(attrs, "message")),
      retryable?: normalize_boolean(Map.get(attrs, :retryable?) || Map.get(attrs, "retryable")),
      details: normalize_details(Map.get(attrs, :details) || Map.get(attrs, "details"))
    }
  end

  defp normalize_atom(value) when is_atom(value), do: value
  defp normalize_atom(_value), do: nil

  defp normalize_message(value) when is_binary(value), do: value
  defp normalize_message(value), do: inspect(value)

  defp normalize_boolean(value) when is_boolean(value), do: value
  defp normalize_boolean(_value), do: false

  defp normalize_details(value) when is_map(value), do: value
  defp normalize_details(_value), do: %{}
end
