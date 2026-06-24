defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Renderer do
  @moduledoc """
  Deterministic backend renderer for structured execution plan Workpads.

  Rendered Markdown is derived only from canonical plan fields. Tracker Workpad
  text can be inspected for render identity, but it is never imported as
  authoritative plan data.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Schema
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.ErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Markdown
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Markdown.Text
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Marker

  @items_key Fields.items()
  @plan_id_key Fields.plan_id()
  @revision_key Fields.revision()

  @spec render(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def render(plan, opts \\ [])

  def render(plan, opts) when is_map(plan) and is_list(opts) do
    with {:ok, valid_plan} <- Schema.validate(plan),
         {:ok, mode} <- render_mode(Keyword.get(opts, :mode, Contract.preview_mode())),
         {:ok, max_items} <- max_items(Keyword.get(opts, :max_items, Contract.max_items())),
         {:ok, heading} <- heading(Keyword.get(opts, :heading, Contract.default_heading())) do
      do_render(valid_plan, mode, heading, max_items)
    else
      {:error, %{code: _code} = reason} -> {:error, reason}
      {:error, reason} -> {:error, rendering_failed(reason)}
    end
  end

  def render(_plan, _opts), do: {:error, rendering_failed("Plan record must be an object.")}

  @spec validate_marker(map(), map()) :: {:ok, map()} | {:error, map()}
  defdelegate validate_marker(marker, plan), to: Marker, as: :validate

  @spec render_schema() :: String.t()
  defdelegate render_schema, to: Contract

  @spec default_heading() :: String.t()
  defdelegate default_heading, to: Contract

  defp do_render(plan, mode, heading, max_items) do
    items = Map.get(plan, @items_key, [])
    visible_items = Enum.take(items, max_items)
    truncated? = length(items) > max_items

    pending_marker = Marker.build(plan, mode, length(visible_items))
    pending_body = Markdown.body(plan, visible_items, heading, pending_marker, truncated?)
    fingerprint = Marker.fingerprint(pending_body)
    final_marker = Marker.put_fingerprint(pending_marker, fingerprint)
    final_body = Markdown.body(plan, visible_items, heading, final_marker, truncated?)

    {:ok,
     %{
       Contract.mode_key() => mode,
       Contract.heading_key() => heading,
       Contract.body_key() => final_body,
       Contract.fingerprint_key() => fingerprint,
       Contract.marker_key() => final_marker,
       @plan_id_key => Map.fetch!(plan, @plan_id_key),
       Contract.plan_revision_key() => Map.fetch!(plan, @revision_key),
       Contract.item_count_key() => length(items),
       Contract.rendered_item_count_key() => length(visible_items),
       Contract.items_truncated_key() => truncated?
     }}
  end

  defp render_mode(mode) when is_binary(mode) do
    if Contract.render_mode?(mode) do
      {:ok, mode}
    else
      invalid_arguments("Unsupported structured plan Workpad render mode #{inspect(mode)}.")
    end
  end

  defp render_mode(mode), do: invalid_arguments("Unsupported structured plan Workpad render mode #{inspect(mode)}.")

  defp heading(value) when is_binary(value) do
    case bounded_heading(value) do
      "" -> invalid_arguments("Workpad heading must be a non-empty string.")
      heading -> {:ok, heading}
    end
  end

  defp heading(_value), do: invalid_arguments("Workpad heading must be a non-empty string.")

  defp max_items(value) when is_integer(value) and value > 0, do: {:ok, min(value, Contract.max_items())}
  defp max_items(_value), do: invalid_arguments("max_items must be a positive integer.")

  defp bounded_heading(value) do
    Text.bounded(value)
  end

  defp invalid_arguments(message), do: {:error, ErrorCodes.invalid_arguments_reason(message)}

  defp rendering_failed({:invalid_arguments, _message} = reason), do: reason

  defp rendering_failed(message) when is_binary(message) do
    %{code: ErrorCodes.rendering_failed(), message: message}
  end
end
