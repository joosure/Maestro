defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ToolResultRecorder do
  @moduledoc """
  Coding PR Delivery Dynamic Tool result recorder.

  This extension-owned adapter interprets tracker typed-tool results for Coding
  PR Delivery producers. Provider domains publish only provider-neutral tool
  results; this module owns the business meaning of those results.
  """

  @behaviour SymphonyElixir.Workflow.Extension.ToolResultRecorder

  alias SymphonyElixir.Workflow.Extension.{Diagnostics, ErrorCodes}
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler

  @recorder_id_suffix ".tracker_tool_result"
  @tracker_source_kind "tracker"
  @tracker_source_kind_atom :tracker
  @invalid_options_message "Coding PR Delivery tool-result recorder options are invalid."

  @impl true
  def id, do: CodingPrDelivery.id() <> @recorder_id_suffix

  @impl true
  def record_tool_result(source_kind, source_context, tool, arguments, result, opts)

  def record_tool_result(source_kind, source_context, tool, arguments, result, opts)
      when source_kind in [@tracker_source_kind, @tracker_source_kind_atom] do
    case validate_opts(opts) do
      {:ok, opts} ->
        TrackerToolResultHandler.record(source_context, tool, arguments, result, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def record_tool_result(_source_kind, _source_context, _tool, _arguments, _result, _opts), do: :ok

  defp validate_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, opts}
    else
      {:error, invalid_options(opts)}
    end
  end

  defp validate_opts(opts), do: {:error, invalid_options(opts)}

  defp invalid_options(opts) do
    %{
      code: ErrorCodes.invalid_tool_result_recorder(),
      message: @invalid_options_message,
      reason: :options_not_keyword,
      value_type: Diagnostics.type_name(opts)
    }
  end
end
