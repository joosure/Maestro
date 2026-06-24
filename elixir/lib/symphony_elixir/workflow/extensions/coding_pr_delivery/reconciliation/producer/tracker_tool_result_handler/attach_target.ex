defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.AttachTarget do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ExternalReferenceContract, as: ExternalReference
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProducerDefaults, as: Defaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields, as: KnownTargetFields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Events
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Payload
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.TargetRegistration
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Values

  @spec record(map(), String.t(), term(), term(), keyword()) :: :ok
  def record(tracker, tool, arguments, payload, opts) when is_map(arguments) do
    metadata = Values.map_value(arguments, ExternalReference.metadata_key()) || %{}

    external_reference =
      Values.map_value(payload, ExternalReference.external_reference_key()) ||
        Values.map_value(payload, ExternalReference.external_reference_snake_key()) ||
        %{}

    with :ok <- change_proposal_reference_kind(arguments),
         {:ok, issue_id} <- canonical_issue_id(tracker, payload, arguments),
         {:ok, url} <- external_reference_url(arguments, external_reference) do
      settings = settings(opts)
      repo = repo_config(settings, opts)

      attrs = %{
        KnownTargetFields.issue_id() => issue_id,
        KnownTargetFields.tracker_kind() => Defaults.tracker_kind(tracker),
        KnownTargetFields.repo_provider_kind() =>
          Values.string_value(arguments, ExternalReference.provider_kind_key()) ||
            Values.string_value(metadata, ExternalReference.provider_kind_key()) ||
            Defaults.repo_provider_kind(repo),
        KnownTargetFields.repository() => Values.string_value(metadata, KnownTargetFields.repository()) || Defaults.repo_repository(repo),
        KnownTargetFields.number() =>
          Values.string_value(arguments, ExternalReference.external_id_key()) ||
            Values.string_value(external_reference, ExternalReference.external_id_camel_key()) ||
            Payload.external_reference_id(external_reference),
        KnownTargetFields.url() => url,
        KnownTargetFields.branch() => Values.string_value(metadata, KnownTargetFields.branch()),
        KnownTargetFields.head_sha() => Values.string_value(metadata, KnownTargetFields.head_sha())
      }

      TargetRegistration.register(attrs, tracker, tool, arguments, opts)
    else
      {:error, reason} ->
        Events.ignored(tracker, tool, arguments, reason_atom(reason), %{error: Diagnostics.error_string(reason)}, opts)
    end
  end

  def record(tracker, tool, arguments, _payload, opts) do
    Events.ignored(tracker, tool, arguments, :invalid_arguments, %{}, opts)
  end

  defp change_proposal_reference_kind(arguments) do
    if Values.string_value(arguments, ExternalReference.reference_kind_key()) == ExternalReference.change_proposal_kind() do
      :ok
    else
      {:error, {:unsupported_reference_kind, ExternalReference.change_proposal_kind()}}
    end
  end

  defp external_reference_url(arguments, external_reference) do
    case Values.string_value(arguments, KnownTargetFields.url()) || Payload.external_reference_url(external_reference) do
      value when is_binary(value) -> {:ok, value}
      nil -> {:error, {:missing_required_argument, KnownTargetFields.url()}}
    end
  end

  defp canonical_issue_id(tracker, payload, arguments) do
    with nil <- Payload.issue_id(payload),
         {:ok, issue_id} <- Values.required_string(arguments, KnownTargetFields.issue_id()) do
      {:ok, normalize_issue_id(tracker, issue_id)}
    else
      issue_id when is_binary(issue_id) -> {:ok, normalize_issue_id(tracker, issue_id)}
      {:error, _reason} = error -> error
    end
  end

  defp normalize_issue_id(tracker, issue_id) when is_map(tracker) and is_binary(issue_id) do
    Defaults.normalize_issue_id(tracker, issue_id)
  end

  defp settings(opts) do
    case Keyword.fetch(opts, :settings) do
      {:ok, settings} when is_map(settings) -> settings
      _other -> Defaults.settings()
    end
  end

  defp repo_config(%{repo: repo}, _opts) when is_map(repo), do: repo

  defp repo_config(_settings, opts) do
    case Keyword.get(opts, :repo) do
      repo when is_map(repo) -> repo
      _repo -> %{}
    end
  end

  defp reason_atom({:missing_required_argument, _field}), do: :missing_required_argument
  defp reason_atom({:unsupported_reference_kind, _expected_kind}), do: :unsupported_reference_kind
end
