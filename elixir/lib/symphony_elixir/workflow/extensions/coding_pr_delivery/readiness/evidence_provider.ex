defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider do
  @moduledoc """
  Coding PR Delivery readiness evidence provider.

  The module is the public provider facade registered through the extension
  contribution surface. It keeps orchestration thin and delegates reference
  resolution, provider fact retrieval, readiness gating, and evidence projection
  to cohesive modules inside the readiness subdomain.
  """

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Readiness.EventEmitterDefaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider.LandReady
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider.Projector
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider.ProviderClient
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider.ReferenceResolver
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.Options

  @spec evidence(Issue.t(), map(), map(), keyword()) :: map()
  def evidence(%Issue{} = issue, context, _facts, opts) when is_map(context) do
    case Options.normalize(opts) do
      {:ok, opts} ->
        evidence_with_options(issue, context, opts)

      {:error, reason} ->
        emit_error(opts, Contract.options_operation(), reason)
        %{}
    end
  end

  def evidence(_issue, _context, _facts, opts) do
    emit_error(opts, Contract.evidence_operation(), %{reason: :invalid_provider_input})
    %{}
  end

  defp evidence_with_options(%Issue{} = issue, context, opts) when is_map(context) do
    with {:ok, repo} <- workflow_repo(context),
         {:ok, reference} <- ReferenceResolver.reference(issue, opts),
         {:ok, facts} <- ProviderClient.facts(repo, reference, opts),
         true <- LandReady.ready?(facts) do
      Projector.evidence(facts, issue)
    else
      :skip ->
        %{}

      false ->
        %{}

      {:error, reason} ->
        emit_error(opts, Contract.evidence_operation(), reason)
        %{}
    end
  end

  defp workflow_repo(%{workflow_settings: settings}) when is_map(settings) do
    case Map.get(settings, :repo) do
      repo when is_map(repo) -> {:ok, repo}
      _repo -> :skip
    end
  end

  defp workflow_repo(_context), do: :skip

  defp emit_error(opts, operation, reason) do
    emit_event_fn(opts).(:warning, Contract.error_event(), %{
      component: Contract.component(),
      error_code: Contract.error_code(),
      operation: operation,
      payload_summary: bounded_reason(reason)
    })

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp emit_event_fn(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      case Keyword.get(opts, Contract.emit_event_fn_key()) do
        emit_event_fn when is_function(emit_event_fn, 3) -> emit_event_fn
        _other -> &EventEmitterDefaults.emit/3
      end
    else
      &EventEmitterDefaults.emit/3
    end
  end

  defp emit_event_fn(_opts), do: &EventEmitterDefaults.emit/3

  defp bounded_reason(reason) when is_map(reason) do
    Map.take(reason, [:reason, :value_type, :reason_type, :exception, :kind, :target_type, :operation])
  end

  defp bounded_reason({reason, details}) when is_atom(reason) and is_map(details) do
    detail_summary = bounded_reason(details)

    detail_summary
    |> Map.delete(:reason)
    |> maybe_put_detail_reason(Map.get(detail_summary, :reason))
    |> Map.put(:reason, reason)
  end

  defp bounded_reason(_reason), do: %{reason: :unexpected_error}

  defp maybe_put_detail_reason(summary, nil), do: summary
  defp maybe_put_detail_reason(summary, detail_reason), do: Map.put(summary, :detail_reason, detail_reason)
end
