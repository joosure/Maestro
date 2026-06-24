defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider.ProviderClient do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Reference, as: KnownTargetReference
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Facts
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts

  @provider_facts_opts_key :provider_facts_opts

  @spec facts(map(), KnownTargetReference.t(), keyword()) :: {:ok, Facts.t()} | :skip | {:error, term()}
  def facts(repo, %KnownTargetReference{} = reference, opts) when is_map(repo) and is_list(opts) do
    with {:ok, target} <- target(reference),
         {:ok, provider_opts} <- provider_facts_opts(opts),
         %Facts{} = facts <- ProviderFacts.facts(repo, target, provider_opts) do
      {:ok, facts}
    else
      :skip -> :skip
      {:error, reason} -> {:error, reason}
    end
  end

  defp provider_facts_opts(opts) when is_list(opts) do
    provider_opts = Keyword.get(opts, @provider_facts_opts_key, [])

    if Keyword.keyword?(provider_opts) do
      {:ok, provider_opts}
    else
      {:error, {:invalid_provider_facts_options, %{reason: :opts_not_keyword, value_type: Diagnostics.detailed_type_atom(provider_opts)}}}
    end
  end

  defp target(%KnownTargetReference{} = reference) do
    target =
      %{}
      |> put_present(:number, reference.number)
      |> put_present(:url, reference.url)
      |> put_present(:branch, reference.branch)

    if map_size(target) > 0 do
      {:ok, target}
    else
      :skip
    end
  end

  defp put_present(map, _key, nil), do: map

  defp put_present(map, key, value) when is_binary(value) do
    case String.trim(value) do
      "" -> map
      _value -> Map.put(map, key, value)
    end
  end

  defp put_present(map, key, value) when is_integer(value), do: Map.put(map, key, value)
  defp put_present(map, _key, _value), do: map
end
