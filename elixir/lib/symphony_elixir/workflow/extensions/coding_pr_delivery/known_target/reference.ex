defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Reference do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields

  defstruct [:number, :url, :branch]

  @number_keys [Fields.number(), Fields.change_proposal_id()]
  @url_key Fields.url()
  @branch_key Fields.branch()

  @type t :: %__MODULE__{
          number: String.t() | nil,
          url: String.t() | nil,
          branch: String.t() | nil
        }

  @spec from_target(KnownTarget.t()) :: t()
  def from_target(%KnownTarget{} = target) do
    %__MODULE__{
      number: target.number,
      url: target.url,
      branch: target.branch
    }
  end

  @spec from_map(map()) :: t() | nil
  def from_map(attrs) when is_map(attrs) do
    url = string_value(attrs, @url_key)

    %__MODULE__{
      number: first_string_value(attrs, @number_keys) || number_from_url(url),
      url: url,
      branch: string_value(attrs, @branch_key)
    }
    |> blank_to_nil()
  end

  def from_map(_attrs), do: nil

  defp blank_to_nil(%__MODULE__{} = reference) do
    if Enum.any?([reference.number, reference.url, reference.branch], &present_string?/1) do
      reference
    end
  end

  defp first_string_value(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, &string_value(map, &1))
  end

  defp string_value(map, key) when is_map(map), do: map |> Map.get(key) |> normalize_string()

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(_value), do: nil

  defp number_from_url(nil), do: nil

  defp number_from_url(url) when is_binary(url) do
    with %URI{path: path} when is_binary(path) <- URI.parse(url),
         [number | _rest] <- path |> String.split("/", trim: true) |> Enum.reverse(),
         true <- String.match?(number, ~r/^\d+$/) do
      number
    else
      _other -> nil
    end
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
end
