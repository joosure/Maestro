defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.TargetReference do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Reference, as: KnownTargetReference
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.ReferenceExtractor
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.Clients
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.Options

  @spec lookup(Issue.t(), Options.t()) :: {:ok, KnownTargetReference.t() | nil} | {:error, term()}
  def lookup(%Issue{} = issue, %Options{} = options) do
    case Clients.custom_change_proposal_reference(issue, options) do
      :default -> default(issue, options)
      {:ok, result} -> normalize_result(result)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec known_target_reference(Issue.t(), Options.t()) :: KnownTargetReference.t() | nil
  def known_target_reference(%Issue{id: issue_id}, %Options{} = options) when is_binary(issue_id) do
    case KnownTarget.Registry.get(issue_id, known_target_registry_opts(options)) do
      %KnownTarget{} = target -> KnownTarget.reference(target)
      _target -> nil
    end
  end

  def known_target_reference(%Issue{}, %Options{}), do: nil

  defp default(%Issue{} = issue, %Options{} = options) do
    with nil <- ReferenceExtractor.from_issue(issue),
         nil <- known_target_reference(issue, options) do
      {:ok, nil}
    else
      %KnownTargetReference{} = reference -> {:ok, reference}
    end
  end

  defp known_target_registry_opts(%Options{known_target_registry: nil}), do: []
  defp known_target_registry_opts(%Options{known_target_registry: registry}), do: [server: registry]

  defp normalize_result({:ok, _target} = result), do: result
  defp normalize_result({:error, _reason} = error), do: error
  defp normalize_result(nil), do: {:ok, nil}
  defp normalize_result(%KnownTargetReference{} = reference), do: {:ok, reference}

  defp normalize_result(target) when is_map(target) do
    {:ok, KnownTargetReference.from_map(target)}
  end

  defp normalize_result(target), do: {:error, {:invalid_change_proposal_reference_result, %{value_type: Diagnostics.type_atom(target)}}}
end
