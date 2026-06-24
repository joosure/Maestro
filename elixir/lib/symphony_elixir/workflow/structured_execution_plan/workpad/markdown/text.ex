defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Markdown.Text do
  @moduledoc """
  Text normalization for workflow structured-plan Markdown projection.

  The renderer emits bounded, redacted text. This module does not inspect
  Workpad Markdown as input.
  """

  alias SymphonyElixir.Observability.Redaction
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Contract

  @spec bounded(term()) :: String.t()
  def bounded(value) when is_binary(value) do
    value
    |> String.replace(~r/[\r\n\t]+/, " ")
    |> String.trim()
    |> Redaction.redact_string()
    |> String.slice(0, Contract.max_text_chars())
  end

  def bounded(value) when is_integer(value), do: Integer.to_string(value)
  def bounded(value) when is_boolean(value), do: to_string(value)
  def bounded(_value), do: ""

  @spec inline_code(term()) :: String.t()
  def inline_code(value) do
    value
    |> bounded()
    |> String.replace("`", "'")
  end
end
