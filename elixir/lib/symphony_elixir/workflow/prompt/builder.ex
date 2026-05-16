defmodule SymphonyElixir.Workflow.Prompt.Builder do
  @moduledoc """
  Builds agent prompts from normalized issue data.
  """

  alias SymphonyElixir.Agent.DynamicTool.{Context, Inventory}
  alias SymphonyElixir.AgentProvider.ToolInventory
  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Observability.Redaction
  alias SymphonyElixir.Workflow
  alias SymphonyElixir.Workflow.Prompt.Template, as: PromptTemplate
  alias SymphonyElixir.Workflow.Readiness

  @render_opts [strict_variables: true, strict_filters: true]

  @spec build_prompt(map(), keyword()) :: String.t()
  def build_prompt(issue, opts \\ []) do
    template =
      Workflow.current()
      |> prompt_template!(issue, opts)
      |> parse_template!(issue, opts)

    try do
      template
      |> Solid.render!(
        %{
          "attempt" => Keyword.get(opts, :attempt),
          "issue" => issue |> structless_map() |> to_solid_map(),
          "repo" => opts |> Keyword.get(:repo, %{}) |> structless_map() |> to_solid_map(),
          "workflow" => issue |> Readiness.facts(opts) |> to_solid_map(),
          "tool_inventory" => tool_inventory(opts)
        },
        @render_opts
      )
      |> IO.iodata_to_binary()
    rescue
      error ->
        ObsLogger.emit(
          :error,
          :prompt_render_failed,
          prompt_event_fields(issue, opts, %{
            workflow_path: Workflow.workflow_file_path(),
            error: ObsLogger.format_error(error),
            prompt_hash: prompt_hash(template)
          })
        )

        reraise(error, __STACKTRACE__)
    end
  end

  defp prompt_template!({:ok, %{prompt_template: prompt}}, _issue, _opts), do: PromptTemplate.select(prompt)

  defp prompt_template!({:error, reason}, issue, opts) do
    ObsLogger.emit(
      :error,
      :prompt_workflow_unavailable,
      prompt_event_fields(issue, opts, %{
        workflow_path: Workflow.workflow_file_path(),
        error: inspect(reason)
      })
    )

    raise RuntimeError, "workflow_unavailable: #{inspect(reason)}"
  end

  defp parse_template!(prompt, issue, opts) when is_binary(prompt) do
    Solid.parse!(prompt)
  rescue
    error ->
      ObsLogger.emit(
        :error,
        :prompt_template_parse_failed,
        prompt_event_fields(issue, opts, %{
          workflow_path: Workflow.workflow_file_path(),
          prompt_hash: prompt_hash(prompt),
          error: ObsLogger.format_error(error),
          payload_summary: Redaction.summarize(prompt, 256)
        })
      )

      reraise %RuntimeError{
                message: "template_parse_error: #{Exception.message(error)} template=#{inspect(prompt)}"
              },
              __STACKTRACE__
  end

  defp structless_map(%_{} = value), do: Map.from_struct(value)
  defp structless_map(value) when is_map(value), do: value
  defp structless_map(_value), do: %{}

  defp to_solid_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), to_solid_value(value)} end)
  end

  defp to_solid_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp to_solid_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp to_solid_value(%Date{} = value), do: Date.to_iso8601(value)
  defp to_solid_value(%Time{} = value), do: Time.to_iso8601(value)
  defp to_solid_value(%_{} = value), do: value |> Map.from_struct() |> to_solid_map()
  defp to_solid_value(value) when is_map(value), do: to_solid_map(value)
  defp to_solid_value(value) when is_list(value), do: Enum.map(value, &to_solid_value/1)
  defp to_solid_value(value), do: value

  defp tool_inventory(opts) when is_list(opts) do
    fallback_policy =
      Keyword.get(
        opts,
        :typed_workflow_tool_fallback_policy,
        Application.get_env(:symphony_elixir, :typed_workflow_tool_fallback_policy, %{})
      )

    render_opts =
      opts
      |> Keyword.get(:agent_provider_kind)
      |> ToolInventory.render_opts()
      |> Keyword.put(:fallback_policy, fallback_policy)

    opts
    |> Context.from_opts()
    |> Inventory.render(render_opts)
  end

  defp prompt_event_fields(issue, opts, extra) when is_list(opts) and is_map(extra) do
    %{
      component: "prompt_builder",
      issue_id: Map.get(issue, :id),
      issue_identifier: Map.get(issue, :identifier),
      run_id: Keyword.get(opts, :run_id),
      correlation_id: Keyword.get(opts, :run_id),
      attempt: Keyword.get(opts, :attempt)
    }
    |> Map.merge(extra)
  end

  defp prompt_hash(prompt), do: Integer.to_string(:erlang.phash2(prompt), 36)
end
