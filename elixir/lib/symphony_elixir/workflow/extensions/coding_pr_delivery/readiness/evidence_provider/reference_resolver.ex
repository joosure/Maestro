defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider.ReferenceResolver do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Reference, as: KnownTargetReference
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.ReferenceExtractor

  @known_target_registry_opts_key :known_target_registry_opts

  @spec reference(Issue.t(), keyword()) :: {:ok, KnownTargetReference.t()} | :skip | {:error, term()}
  def reference(%Issue{} = issue, opts) when is_list(opts) do
    case ReferenceExtractor.from_issue(issue) do
      %KnownTargetReference{} = reference -> {:ok, reference}
      nil -> known_target_reference(issue, opts)
    end
  end

  defp known_target_reference(%Issue{id: issue_id}, opts) when is_binary(issue_id) do
    with {:ok, registry_opts} <- known_target_registry_opts(opts) do
      case KnownTarget.Registry.get(issue_id, registry_opts) do
        %KnownTarget{} = target -> target_reference(target)
        nil -> :skip
        {:error, reason} -> {:error, {:known_target_registry_lookup_failed, bounded_registry_reason(reason)}}
      end
    end
  end

  defp known_target_reference(_issue, _opts), do: :skip

  defp known_target_registry_opts(opts) when is_list(opts) do
    registry_opts = Keyword.get(opts, @known_target_registry_opts_key, [])

    if Keyword.keyword?(registry_opts) do
      {:ok, registry_opts}
    else
      {:error,
       {:invalid_known_target_registry_opts,
        %{
          reason: :opts_not_keyword,
          value_type: Diagnostics.detailed_type_atom(registry_opts)
        }}}
    end
  end

  defp target_reference(%KnownTarget{} = target) do
    {:ok, KnownTarget.reference(target)}
  end

  defp bounded_registry_reason(reason) when is_atom(reason), do: %{reason: reason}

  defp bounded_registry_reason({reason, details}) when is_atom(reason) and is_map(details) do
    Map.put(bounded_registry_reason(details), :reason, reason)
  end

  defp bounded_registry_reason(details) when is_map(details) do
    Map.take(details, [:reason, :value_type, :reason_type, :exception, :kind])
  end

  defp bounded_registry_reason(reason), do: %{reason: :unexpected_error, value_type: Diagnostics.detailed_type_atom(reason)}
end
