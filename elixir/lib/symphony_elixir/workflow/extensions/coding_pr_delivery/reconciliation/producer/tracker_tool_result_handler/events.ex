defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Events do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProducerDefaults, as: Defaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields, as: KnownTargetFields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config, as: ReconciliationConfig
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Router
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Values

  @spec ignored(map(), String.t(), term(), atom(), map(), keyword()) :: :ok
  def ignored(tracker, tool, arguments, reason, fields, opts)
      when is_map(tracker) and is_atom(reason) and is_map(fields) do
    if emit_ignored?(reason, opts) do
      emit_ignored_event(tracker, tool, arguments, reason, fields, opts)
    end

    :ok
  end

  @spec ignored_reason(term()) :: atom()
  def ignored_reason({:error, {:missing_required_argument, _field}}), do: :missing_required_argument
  def ignored_reason({:error, {:invalid_known_target_registry_opts, _type}}), do: :invalid_options
  def ignored_reason({:error, _reason}), do: :tracker_tool_result_unavailable
  def ignored_reason({:ok, []}), do: :issue_not_found
  def ignored_reason({:ok, %ReconciliationConfig{enabled?: false}}), do: :reconciliation_disabled
  def ignored_reason({:ok, nil}), do: :change_proposal_reference_unavailable
  def ignored_reason(nil), do: :change_proposal_reference_unavailable
  def ignored_reason(false), do: :source_route_mismatch
  def ignored_reason(_other), do: :tracker_tool_result_unavailable

  @spec ignored_details(term()) :: map()
  def ignored_details({:error, reason}), do: %{error: Diagnostics.error_string(reason)}
  def ignored_details(_other), do: %{}

  @spec invalid_options(map(), String.t(), term()) :: :ok
  def invalid_options(tracker, tool, opts) when is_map(tracker) and is_binary(tool) do
    reason = Diagnostics.invalid_options(opts)

    Defaults.emit_event(:warning, Contract.event(:tracker_tool_result_ignored), %{
      component: Contract.component(),
      producer: Contract.producer(:tracker_tool_result),
      tracker_kind: Defaults.tracker_kind(tracker),
      dynamic_tool_name: tool,
      ignore_reason: Contract.reason_name(:invalid_options),
      error: Diagnostics.error_string(reason)
    })

    :ok
  end

  defp emit_ignored_event(tracker, tool, arguments, reason, fields, opts) do
    event_fields =
      fields
      |> Map.merge(%{
        component: Contract.component(),
        producer: Contract.producer(:tracker_tool_result),
        tracker_kind: Defaults.tracker_kind(tracker),
        dynamic_tool_name: tool,
        issue_id: Values.string_value(arguments, KnownTargetFields.issue_id()),
        ignore_reason: Contract.reason_name(reason)
      })

    opts
    |> Keyword.get(:emit_event_fn, &Defaults.emit_event/3)
    |> then(& &1.(ignored_event_level(reason), Contract.event(:tracker_tool_result_ignored), event_fields))

    :ok
  end

  defp emit_ignored?(:missing_workflow_capability, opts), do: Router.diagnostics_enabled?(opts)
  defp emit_ignored?(_reason, _opts), do: true

  defp ignored_event_level(:known_target_registration_failed), do: :warning
  defp ignored_event_level(_reason), do: :debug
end
