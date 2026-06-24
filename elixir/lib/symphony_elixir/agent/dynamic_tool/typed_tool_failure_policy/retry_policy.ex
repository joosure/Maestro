defmodule SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.RetryPolicy do
  @moduledoc false

  defstruct blocked_code: nil,
            message: nil

  @type t :: %__MODULE__{
          blocked_code: String.t(),
          message: String.t()
        }

  @spec new(String.t(), String.t()) :: {:ok, t()} | :error
  def new(blocked_code, message) do
    with {:ok, blocked_code} <- normalize_text(blocked_code),
         {:ok, message} <- normalize_text(message) do
      {:ok, %__MODULE__{blocked_code: blocked_code, message: message}}
    end
  end

  @spec new!(String.t(), String.t()) :: t()
  def new!(blocked_code, message) do
    case new(blocked_code, message) do
      {:ok, policy} -> policy
      :error -> raise ArgumentError, "typed tool failure retry policy requires non-empty blocked_code and message"
    end
  end

  @spec normalize(t()) :: {:ok, t()} | :error
  def normalize(%__MODULE__{blocked_code: blocked_code, message: message}), do: new(blocked_code, message)
  def normalize(_policy), do: :error

  @spec normalize_many!(map()) :: %{String.t() => t()}
  def normalize_many!(policies) when is_map(policies) do
    Map.new(policies, fn {code, policy} ->
      {normalize_code!(code), normalize_policy!(policy)}
    end)
  end

  def normalize_many!(_policies) do
    raise ArgumentError, "typed tool failure retry policies must be a map of error code to RetryPolicy struct"
  end

  defp normalize_policy!(policy) do
    case normalize(policy) do
      {:ok, policy} ->
        policy

      :error ->
        raise ArgumentError, "typed tool failure retry policy values must be RetryPolicy structs"
    end
  end

  defp normalize_code!(code) when is_binary(code) do
    case String.trim(code) do
      "" -> raise ArgumentError, "typed tool failure retry policy code must be a non-empty string"
      trimmed -> trimmed
    end
  end

  defp normalize_code!(_code) do
    raise ArgumentError, "typed tool failure retry policy code must be a string"
  end

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> :error
      trimmed -> {:ok, trimmed}
    end
  end

  defp normalize_text(_value), do: :error
end
