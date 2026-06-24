defmodule SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.ResourceIdentity do
  @moduledoc false

  defstruct kind: nil,
            id: nil

  @type t :: %__MODULE__{
          kind: String.t(),
          id: term()
        }

  @spec new(String.t(), term()) :: {:ok, t()} | :error
  def new(kind, id) when is_binary(kind) and not is_nil(id) do
    case String.trim(kind) do
      "" -> :error
      kind -> {:ok, %__MODULE__{kind: kind, id: id}}
    end
  end

  def new(_kind, _id), do: :error

  @spec new!(String.t(), term()) :: t()
  def new!(kind, id) do
    case new(kind, id) do
      {:ok, identity} -> identity
      :error -> raise ArgumentError, "typed tool failure resource identity requires non-empty kind and non-nil id"
    end
  end

  @spec normalize(t()) :: t() | nil
  def normalize(%__MODULE__{kind: kind, id: id}) do
    case new(kind, id) do
      {:ok, identity} -> identity
      :error -> nil
    end
  end

  def normalize(_identity), do: nil
end
