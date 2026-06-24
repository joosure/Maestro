defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.Result do
  @moduledoc """
  Result envelopes and bounded summaries for structured-plan Workpad writing.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Contract, as: RenderingContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Markdown.Text
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.ErrorCodes

  @success_key "success"
  @status_key "status"
  @reason_key "reason"
  @gate_key "gate"
  @code_key :code
  @message_key :message
  @details_key :details
  @tracker_result_key "tracker_result"
  @result_type_key "result_type"
  @tracker_tool_key "tracker_tool"
  @workpad_key "workpad"
  @workpad_state_key "workpad_state"
  @rendered_workpad_key "rendered_workpad"
  @stored_plan_revision_key "stored_plan_revision"
  @error_key "error"
  @keys_key "keys"

  @action_key "action"
  @state_key "state"
  @known_state "known"
  @missing_state "missing"
  @write_action "write"

  @created_status "created"
  @updated_status "updated"
  @written_status "written"
  @skipped_status "skipped"

  @workpad_id_key "id"
  @workpad_provider_key "provider"
  @workpad_provider_ref_key "provider_ref"
  @workpad_url_key "url"
  @workpad_created_key "created"
  @workpad_updated_key "updated"

  @map_result_type "map"
  @list_result_type "list"
  @tuple_result_type "tuple"
  @string_result_type "string"
  @atom_result_type "atom"
  @number_result_type "number"
  @term_result_type "term"

  @workpad_summary_keys [
    @workpad_id_key,
    @workpad_provider_key,
    @workpad_provider_ref_key,
    @workpad_url_key,
    @workpad_created_key,
    @workpad_updated_key
  ]
  @error_summary_keys ~w(code message)
  @atom_error_summary_keys [:code, :message]

  @spec gate_disabled(String.t()) :: map()
  def gate_disabled(gate) when is_binary(gate) do
    %{
      @success_key => true,
      @status_key => @skipped_status,
      @reason_key => ErrorCodes.render_workpad_gate_disabled(),
      @gate_key => gate
    }
  end

  @spec success(map(), map(), map(), map(), map()) :: map()
  def success(plan, rendered, decision, tracker_result, updated_plan) do
    %{
      @success_key => true,
      @status_key => Map.fetch!(tracker_result, @status_key),
      Fields.plan_id() => Map.fetch!(plan, Fields.plan_id()),
      RenderingContract.plan_revision_key() => Map.fetch!(plan, Fields.revision()),
      @stored_plan_revision_key => Map.fetch!(updated_plan, Fields.revision()),
      RenderingContract.fingerprint_key() => Map.fetch!(rendered, RenderingContract.fingerprint_key()),
      @tracker_tool_key => Map.get(tracker_result, @tracker_tool_key),
      @workpad_state_key => Map.delete(decision, action_key()),
      @rendered_workpad_key => rendered_workpad(rendered),
      @workpad_key => Map.get(tracker_result, @workpad_key)
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  @spec tracker_success(String.t(), map(), String.t()) :: map()
  def tracker_success(tool, workpad, workpad_id) when is_binary(tool) and is_map(workpad) and is_binary(workpad_id) do
    %{
      @status_key => write_status(workpad),
      RenderingContract.workpad_id_key() => workpad_id,
      @workpad_key => bounded_workpad(workpad),
      @tracker_tool_key => tool
    }
  end

  @spec failure(String.t()) :: map()
  def failure(message) when is_binary(message), do: %{@code_key => ErrorCodes.rendering_failed(), @message_key => message}

  @spec failure(String.t(), map()) :: map()
  def failure(message, details) when is_binary(message) and is_map(details) do
    %{@code_key => ErrorCodes.rendering_failed(), @message_key => message, @details_key => details}
  end

  @spec tracker_failure(term()) :: map()
  def tracker_failure({:failure, payload}) do
    failure("Tracker Workpad write failed.", %{@tracker_result_key => bounded_tracker_result(payload)})
  end

  def tracker_failure({:error, reason}) do
    failure("Tracker Workpad write failed.", %{@reason_key => Text.bounded(inspect(reason))})
  end

  def tracker_failure({:unsupported, value}) do
    failure("Tracker Workpad write returned an unsupported result.", %{@result_type_key => result_type(value)})
  end

  @spec missing_comment_metadata(term()) :: map()
  def missing_comment_metadata(payload) do
    failure("Tracker Workpad write did not return comment metadata.", %{@tracker_result_key => bounded_tracker_result(payload)})
  end

  @spec action_key() :: String.t()
  def action_key, do: @action_key

  @spec state_key() :: String.t()
  def state_key, do: @state_key

  @spec known_state() :: String.t()
  def known_state, do: @known_state

  @spec missing_state() :: String.t()
  def missing_state, do: @missing_state

  @spec write_action() :: String.t()
  def write_action, do: @write_action

  @spec created_status() :: String.t()
  def created_status, do: @created_status

  @spec updated_status() :: String.t()
  def updated_status, do: @updated_status

  @spec written_status() :: String.t()
  def written_status, do: @written_status

  @spec skipped_status() :: String.t()
  def skipped_status, do: @skipped_status

  defp rendered_workpad(rendered) do
    %{
      RenderingContract.heading_key() => Map.fetch!(rendered, RenderingContract.heading_key()),
      RenderingContract.fingerprint_key() => Map.fetch!(rendered, RenderingContract.fingerprint_key()),
      RenderingContract.item_count_key() => Map.fetch!(rendered, RenderingContract.item_count_key()),
      RenderingContract.rendered_item_count_key() => Map.fetch!(rendered, RenderingContract.rendered_item_count_key()),
      RenderingContract.items_truncated_key() => Map.fetch!(rendered, RenderingContract.items_truncated_key())
    }
  end

  defp write_status(%{@workpad_created_key => true}), do: @created_status
  defp write_status(%{@workpad_updated_key => true}), do: @updated_status
  defp write_status(_comment), do: @written_status

  defp bounded_workpad(workpad) do
    workpad
    |> Map.take(@workpad_summary_keys)
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp bounded_tracker_result(%{@error_key => %{} = error}) do
    %{@error_key => error |> Map.take(@error_summary_keys) |> Map.reject(fn {_key, value} -> is_nil(value) end)}
  end

  defp bounded_tracker_result(%{error: %{} = error}) do
    %{@error_key => error |> Map.take(@atom_error_summary_keys) |> Enum.map(fn {key, value} -> {to_string(key), value} end) |> Map.new()}
  end

  defp bounded_tracker_result(%{} = payload), do: %{@keys_key => payload |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()}
  defp bounded_tracker_result(payload), do: %{@result_type_key => result_type(payload)}

  defp result_type(value) do
    cond do
      is_map(value) -> @map_result_type
      is_list(value) -> @list_result_type
      is_tuple(value) -> @tuple_result_type
      is_binary(value) -> @string_result_type
      is_atom(value) -> @atom_result_type
      is_number(value) -> @number_result_type
      true -> @term_result_type
    end
  end
end
