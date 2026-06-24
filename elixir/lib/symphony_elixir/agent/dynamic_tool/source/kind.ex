defmodule SymphonyElixir.Agent.DynamicTool.Source.Kind do
  @moduledoc false

  @type t :: String.t() | nil

  @spec normalize(term()) :: t()
  def normalize(kind) when is_binary(kind) do
    case String.trim(kind) do
      "" -> nil
      normalized -> normalized
    end
  end

  def normalize(nil), do: nil
  def normalize(_kind), do: nil

  @spec normalize!(term()) :: t()
  def normalize!(kind) when is_binary(kind) or is_nil(kind), do: normalize(kind)

  def normalize!(kind) do
    raise ArgumentError, "invalid dynamic tool source kind: #{inspect(kind)}"
  end
end
