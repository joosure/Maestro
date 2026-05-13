defmodule SymphonyElixir.Workflow.Prompt.Template do
  @moduledoc """
  Owns workflow prompt template defaults and default selection.
  """

  @default_template """
  You are working on an issue.

  Identifier: {{ issue.identifier }}
  Title: {{ issue.title }}

  Body:
  {% if issue.description %}
  {{ issue.description }}
  {% else %}
  No description provided.
  {% endif %}
  """

  @spec default_template() :: String.t()
  def default_template, do: @default_template

  @spec select(String.t() | nil) :: String.t()
  def select(prompt) when is_binary(prompt) do
    if String.trim(prompt) == "" do
      default_template()
    else
      prompt
    end
  end

  def select(_prompt), do: default_template()
end
