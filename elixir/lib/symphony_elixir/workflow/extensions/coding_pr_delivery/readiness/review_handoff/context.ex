defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Context do
  @moduledoc """
  Runtime option projection for Coding PR Delivery review handoff.

  This module is the review-handoff adapter boundary for raw option keys. Policy
  orchestration and rule modules consume this normalized context instead of
  reading raw keyword options directly.
  """

  @target_state_name_key :target_state_name

  @type t :: %{
          optional(:target_state_name) => String.t()
        }

  @spec build(keyword()) :: t()
  def build(opts) when is_list(opts) do
    %{}
    |> maybe_put(:target_state_name, target_state_name_from_opts(opts))
  end

  @spec target_state_name(t()) :: String.t() | nil
  def target_state_name(context) when is_map(context), do: Map.get(context, :target_state_name)
  def target_state_name(_context), do: nil

  defp target_state_name_from_opts(opts) do
    case Keyword.get(opts, @target_state_name_key) do
      value when is_binary(value) -> present_string(value)
      value when is_atom(value) and not is_nil(value) -> value |> Atom.to_string() |> present_string()
      value when is_integer(value) -> value |> Integer.to_string() |> present_string()
      _value -> nil
    end
  end

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
