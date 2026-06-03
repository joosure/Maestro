defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.WorkpadWriter do
  @moduledoc """
  Gated backend writer for rendered structured execution plan Workpads.

  This module is not a Dynamic Tool source. Callers must explicitly provide a
  tracker Workpad typed-tool executor, and the structured-plan render gate must
  be enabled. Rendered Workpad text remains one-way output from canonical plan
  state; tracker Workpad identity is carried by `workpad_id`, not by comment
  body inspection.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.WorkpadRenderer

  @enabled_gate "workflow.structured_execution_plan.enabled"
  @render_workpad_gate "workflow.structured_execution_plan.render_workpad"

  @type tracker_executor :: (String.t(), map(), keyword() -> {:success, term()} | {:failure, term()} | {:error, term()})

  @spec write(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def write(plan_id, opts \\ [])

  def write(plan_id, opts) when is_binary(plan_id) and is_list(opts) do
    with :ok <- ensure_gates(opts),
         {:ok, plan} <- Store.fetch(plan_id, store_opts(opts)),
         :ok <- ensure_writable_plan(plan),
         {:ok, rendered} <- WorkpadRenderer.render(plan, render_opts(opts)),
         {:ok, decision} <- write_decision(plan, opts),
         {:ok, result} <- maybe_write(plan, rendered, decision, opts),
         {:ok, updated_plan} <- maybe_record_marker(plan, rendered, result, opts) do
      {:ok, success_result(plan, rendered, decision, result, updated_plan)}
    else
      {:skip, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  def write(_plan_id, _opts), do: {:error, rendering_failed("plan_id must be a string.")}

  defp ensure_gates(opts) do
    gates = Keyword.get(opts, :gates, Contract.gate_defaults())
    structured_enabled? = gate_enabled?(gates, @enabled_gate)
    render_enabled? = gate_enabled?(gates, @render_workpad_gate)

    cond do
      structured_enabled? and render_enabled? ->
        :ok

      render_enabled? and not structured_enabled? ->
        {:error, rendering_failed("Structured plan Workpad rendering requires structured execution plans to be enabled.")}

      true ->
        {:skip,
         %{
           "success" => true,
           "status" => "skipped",
           "reason" => "render_workpad_gate_disabled",
           "gate" => @render_workpad_gate
         }}
    end
  end

  defp gate_enabled?(gates, key) when is_map(gates), do: Map.get(gates, key) == true
  defp gate_enabled?(_gates, _key), do: false

  defp ensure_writable_plan(%{"status" => status, "plan_id" => plan_id}) when status in ["closed", "superseded"] do
    {:error,
     rendering_failed(
       "Closed or superseded structured execution plans do not accept Workpad rendering.",
       %{"plan_id" => plan_id, "status" => status}
     )}
  end

  defp ensure_writable_plan(_plan), do: :ok

  defp write_decision(plan, _opts) do
    case get_in(plan, ["rendering", "workpad_id"]) do
      workpad_id when is_binary(workpad_id) and workpad_id != "" ->
        {:ok, %{"action" => "write", "state" => "known", "workpad_id" => workpad_id}}

      _workpad_id ->
        {:ok, %{"action" => "write", "state" => "missing"}}
    end
  end

  defp maybe_write(plan, rendered, %{"action" => "write"} = decision, opts) do
    with {:ok, executor} <- tracker_executor(opts),
         {:ok, tool} <- tracker_tool(plan, opts),
         {:ok, workpad} <- execute_tracker_write(executor, tool, tracker_arguments(plan, rendered, decision, opts), opts),
         {:ok, workpad_id} <- workpad_id(workpad) do
      {:ok,
       %{
         "status" => write_status(workpad),
         "workpad_id" => workpad_id,
         "workpad" => bounded_workpad(workpad),
         "tracker_tool" => tool
       }}
    end
  end

  defp maybe_record_marker(plan, rendered, %{"workpad_id" => workpad_id}, opts) when is_binary(workpad_id) do
    marker = rendered |> Map.fetch!("marker") |> Map.put("workpad_id", workpad_id)

    case Store.record_render_marker(Map.fetch!(plan, "plan_id"), marker, Map.fetch!(plan, "revision"), store_opts(opts)) do
      {:ok, updated_plan} ->
        {:ok, updated_plan}

      {:error, reason} ->
        {:error, rendering_failed("Rendered Workpad marker could not be recorded.", %{"reason" => reason})}
    end
  end

  defp maybe_record_marker(plan, _rendered, _result, _opts), do: {:ok, plan}

  defp execute_tracker_write(executor, tool, arguments, opts) do
    case executor.(tool, arguments, Keyword.get(opts, :tracker_opts, [])) do
      {:success, payload} ->
        extract_comment(payload)

      {:failure, payload} ->
        {:error, rendering_failed("Tracker Workpad write failed.", %{"tracker_result" => bounded_tracker_result(payload)})}

      {:error, reason} ->
        {:error, rendering_failed("Tracker Workpad write failed.", %{"reason" => bounded_text(inspect(reason))})}

      other ->
        {:error, rendering_failed("Tracker Workpad write returned an unsupported result.", %{"result_type" => result_type(other)})}
    end
  end

  defp extract_comment(%{"data" => %{"comment" => comment}}) when is_map(comment), do: {:ok, comment}
  defp extract_comment(%{"comment" => comment}) when is_map(comment), do: {:ok, comment}
  defp extract_comment(%{"payload" => %{"data" => %{"comment" => comment}}}) when is_map(comment), do: {:ok, comment}
  defp extract_comment(%{"payload" => %{"comment" => comment}}) when is_map(comment), do: {:ok, comment}

  defp extract_comment(payload) do
    {:error, rendering_failed("Tracker Workpad write did not return comment metadata.", %{"tracker_result" => bounded_tracker_result(payload)})}
  end

  defp tracker_arguments(plan, rendered, decision, _opts) do
    heading = Map.fetch!(rendered, "heading")
    workpad_id = Map.get(decision, "workpad_id") || get_in(plan, ["rendering", "workpad_id"])

    %{
      "issue_id" => Map.fetch!(plan, "issue_id"),
      "heading" => heading,
      "body" => Map.fetch!(rendered, "body"),
      "mode" => "replace"
    }
    |> maybe_put_map("workpad_id", workpad_id)
  end

  defp tracker_executor(opts) do
    case Keyword.get(opts, :tracker_executor) do
      executor when is_function(executor, 3) -> {:ok, executor}
      _executor -> {:error, rendering_failed("tracker_executor function is required when Workpad rendering is enabled.")}
    end
  end

  defp tracker_tool(plan, opts) do
    case Keyword.get(opts, :tracker_tool) || default_tracker_tool(Map.get(plan, "tracker_kind")) do
      tool when is_binary(tool) -> {:ok, tool}
      _tool -> {:error, rendering_failed("A supported tracker Workpad tool is required.")}
    end
  end

  defp default_tracker_tool("linear"), do: "linear_upsert_workpad"
  defp default_tracker_tool("tapd"), do: "tapd_upsert_workpad"
  defp default_tracker_tool(_tracker_kind), do: nil

  defp workpad_id(%{"id" => id}) when is_binary(id), do: {:ok, id}
  defp workpad_id(_workpad), do: {:error, rendering_failed("Tracker Workpad write did not return a workpad id.")}

  defp write_status(%{"created" => true}), do: "created"
  defp write_status(%{"updated" => true}), do: "updated"
  defp write_status(_comment), do: "written"

  defp bounded_workpad(workpad) do
    workpad
    |> Map.take(~w(id provider provider_ref url created updated))
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp bounded_tracker_result(%{"error" => %{} = error}) do
    %{"error" => error |> Map.take(~w(code message)) |> Map.reject(fn {_key, value} -> is_nil(value) end)}
  end

  defp bounded_tracker_result(%{error: %{} = error}) do
    %{"error" => error |> Map.take([:code, :message]) |> Enum.map(fn {key, value} -> {to_string(key), value} end) |> Map.new()}
  end

  defp bounded_tracker_result(%{} = payload), do: %{"keys" => payload |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()}
  defp bounded_tracker_result(payload), do: %{"result_type" => result_type(payload)}

  defp success_result(plan, rendered, decision, result, updated_plan) do
    %{
      "success" => true,
      "status" => Map.fetch!(result, "status"),
      "plan_id" => Map.fetch!(plan, "plan_id"),
      "plan_revision" => Map.fetch!(plan, "revision"),
      "stored_plan_revision" => Map.fetch!(updated_plan, "revision"),
      "fingerprint" => Map.fetch!(rendered, "fingerprint"),
      "tracker_tool" => Map.get(result, "tracker_tool"),
      "workpad_state" => Map.delete(decision, "action"),
      "rendered_workpad" => %{
        "heading" => Map.fetch!(rendered, "heading"),
        "fingerprint" => Map.fetch!(rendered, "fingerprint"),
        "item_count" => Map.fetch!(rendered, "item_count"),
        "rendered_item_count" => Map.fetch!(rendered, "rendered_item_count"),
        "items_truncated" => Map.fetch!(rendered, "items_truncated")
      },
      "workpad" => Map.get(result, "workpad")
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp store_opts(opts) do
    case Keyword.get(opts, :server) || Keyword.get(opts, :structured_execution_plan_store) do
      nil -> []
      server -> [server: server]
    end
  end

  defp render_opts(opts) do
    [mode: "write"]
    |> maybe_put_keyword(:heading, Keyword.get(opts, :heading))
    |> maybe_put_keyword(:max_items, Keyword.get(opts, :max_items))
  end

  defp maybe_put_map(map, _key, nil), do: map
  defp maybe_put_map(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_keyword(opts, _key, nil), do: opts
  defp maybe_put_keyword(opts, key, value), do: Keyword.put(opts, key, value)

  defp bounded_text(text) when is_binary(text) do
    text
    |> String.replace(~r/[\r\n\t]+/, " ")
    |> String.slice(0, 160)
  end

  defp result_type(value) do
    cond do
      is_map(value) -> "map"
      is_list(value) -> "list"
      is_tuple(value) -> "tuple"
      is_binary(value) -> "string"
      is_atom(value) -> "atom"
      is_number(value) -> "number"
      true -> "term"
    end
  end

  defp rendering_failed(message), do: %{code: "rendering_failed", message: message}

  defp rendering_failed(message, details) do
    %{code: "rendering_failed", message: message, details: details}
  end
end
