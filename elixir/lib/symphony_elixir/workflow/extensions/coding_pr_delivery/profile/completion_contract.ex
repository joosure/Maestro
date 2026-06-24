defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile.CompletionContract do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile.Routes

  @tracker_handoff_expectation "Tracker comment or status surface records the result."

  @base %{
    required_outputs: [
      "Repository changes committed, or an explicit explanation that no code change is required.",
      "Validation evidence recorded.",
      "Blocking failures summarized for the operator and tracker audience."
    ],
    allowed_completion_routes: [],
    evidence_requirements: [
      "Test, check, or manual validation evidence when available.",
      "Change proposal or equivalent handoff link when required by profile options."
    ],
    handoff_expectations: []
  }

  @spec build(term()) :: map()
  def build(options) do
    enabled_completion_route_keys = Routes.enabled_completion_route_keys(options)

    %{
      @base
      | allowed_completion_routes: Enum.map(enabled_completion_route_keys, &Atom.to_string/1),
        handoff_expectations: handoff_expectations(enabled_completion_route_keys)
    }
  end

  defp handoff_expectations(route_keys) when is_list(route_keys) do
    [
      "Handoff records one allowed completion route: #{route_keys |> Enum.map(&Atom.to_string/1) |> sentence_join()}.",
      @tracker_handoff_expectation
    ]
  end

  defp sentence_join([]), do: "No"
  defp sentence_join([label]), do: label
  defp sentence_join([left, right]), do: "#{left} or #{right}"

  defp sentence_join(labels) when is_list(labels) do
    {last, rest_reversed} = List.pop_at(Enum.reverse(labels), 0)

    rest_reversed
    |> Enum.reverse()
    |> Enum.join(", ")
    |> Kernel.<>(", or #{last}")
  end
end
