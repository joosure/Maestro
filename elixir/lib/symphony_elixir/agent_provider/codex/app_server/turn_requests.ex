defmodule SymphonyElixir.AgentProvider.Codex.AppServer.TurnRequests do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.AppServer.{EventFields, Messages, Protocol}
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @non_interactive_tool_input_answer "This is a non-interactive session. Operator input is unavailable."

  @type on_message :: (map() -> term())

  @type request :: %{
          port: term(),
          method: String.t(),
          payload: map(),
          payload_string: String.t(),
          on_message: on_message(),
          metadata: map(),
          auto_approve_requests: boolean(),
          turn_context: map()
        }

  @type handle_result :: :input_required | :approved | :approval_required | :unhandled

  @spec handle(request()) :: handle_result()
  def handle(
        %{
          method: "item/commandExecution/requestApproval",
          payload: %{"id" => id}
        } = request
      ) do
    approve_or_require(request, id, "acceptForSession")
  end

  def handle(%{
        port: port,
        method: "item/tool/call",
        payload: %{"id" => id, "params" => params} = payload,
        payload_string: payload_string,
        on_message: on_message,
        metadata: metadata,
        turn_context: turn_context
      }) do
    tool_name = tool_call_name(params)
    result = unsupported_app_server_tool_call_result(tool_name)

    Protocol.send_message(port, %{
      "id" => id,
      "result" => result
    })

    ObsLogger.emit(
      :warning,
      :codex_unsupported_tool_call,
      EventFields.turn(turn_context, %{
        tool_name: tool_name,
        payload_summary: EventFields.stream_summary(payload),
        reason: "app_server_tool_call_not_supported"
      })
    )

    Messages.emit(
      on_message,
      :unsupported_tool_call,
      %{payload: payload, raw: payload_string, tool_result: result},
      metadata
    )

    :approved
  end

  def handle(
        %{
          method: method,
          payload: %{"id" => id}
        } = request
      )
      when method in ["execCommandApproval", "applyPatchApproval"] do
    approve_or_require(request, id, "approved_for_session")
  end

  def handle(
        %{
          method: "item/fileChange/requestApproval",
          payload: %{"id" => id}
        } = request
      ) do
    approve_or_require(request, id, "acceptForSession")
  end

  def handle(
        %{
          method: "item/tool/requestUserInput",
          payload: %{"id" => id, "params" => params}
        } = request
      ) do
    maybe_auto_answer_tool_request_user_input(request, id, params)
  end

  def handle(
        %{
          method: "mcpServer/elicitation/request",
          payload: %{"id" => id, "params" => params}
        } = request
      ) do
    if mcp_elicitation_approval_request?(params) do
      accept_or_require_mcp_elicitation(request, id)
    else
      :input_required
    end
  end

  def handle(_request) do
    :unhandled
  end

  @spec needs_input?(String.t(), map()) :: boolean()
  def needs_input?(method, payload)
      when is_binary(method) and is_map(payload) do
    String.starts_with?(method, "turn/") && input_required_method?(method, payload)
  end

  def needs_input?(_method, _payload), do: false

  defp unsupported_app_server_tool_call_result(tool_name) do
    output =
      Jason.encode!(
        %{
          "error" => %{
            "code" => "unsupported_app_server_tool_call",
            "message" => "Codex app-server tool calls are not a Symphony Dynamic Tool execution path. Use the session MCP dynamic-tool bridge.",
            "tool" => tool_name
          }
        },
        pretty: true
      )

    %{
      "success" => false,
      "output" => output,
      "contentItems" => dynamic_tool_content_items(output)
    }
  end

  defp dynamic_tool_content_items(output) when is_binary(output) do
    [
      %{
        "type" => "inputText",
        "text" => output
      }
    ]
  end

  defp approve_or_require(
         %{
           port: port,
           payload: payload,
           payload_string: payload_string,
           on_message: on_message,
           metadata: metadata,
           auto_approve_requests: true,
           turn_context: turn_context
         },
         id,
         decision
       ) do
    Protocol.send_message(port, %{"id" => id, "result" => %{"decision" => decision}})

    ObsLogger.emit(
      :info,
      :codex_approval_requested,
      EventFields.turn(turn_context, %{
        payload_summary: EventFields.stream_summary(payload),
        policy_action: "auto_approved"
      })
    )

    Messages.emit(
      on_message,
      :approval_auto_approved,
      %{payload: payload, raw: payload_string, decision: decision},
      metadata
    )

    :approved
  end

  defp approve_or_require(
         %{auto_approve_requests: false},
         _id,
         _decision
       ) do
    :approval_required
  end

  defp accept_or_require_mcp_elicitation(
         %{
           port: port,
           payload: payload,
           payload_string: payload_string,
           on_message: on_message,
           metadata: metadata,
           auto_approve_requests: true,
           turn_context: turn_context
         },
         id
       ) do
    Protocol.send_message(port, %{"id" => id, "result" => %{"action" => "accept"}})

    ObsLogger.emit(
      :info,
      :codex_approval_requested,
      EventFields.turn(turn_context, %{
        payload_summary: EventFields.stream_summary(payload),
        policy_action: "auto_approved"
      })
    )

    Messages.emit(
      on_message,
      :approval_auto_approved,
      %{payload: payload, raw: payload_string, decision: "accept"},
      metadata
    )

    :approved
  end

  defp accept_or_require_mcp_elicitation(%{auto_approve_requests: false}, _id), do: :approval_required

  defp mcp_elicitation_approval_request?(params) when is_map(params) do
    meta = Map.get(params, "_meta") || Map.get(params, :_meta) || %{}

    Map.get(meta, "codex_approval_kind") == "mcp_tool_call" or
      Map.get(meta, :codex_approval_kind) == "mcp_tool_call" or
      Map.get(meta, "codex_request_type") == "approval_request" or
      Map.get(meta, :codex_request_type) == "approval_request"
  end

  defp mcp_elicitation_approval_request?(_params), do: false

  defp maybe_auto_answer_tool_request_user_input(
         %{
           port: port,
           payload: payload,
           payload_string: payload_string,
           on_message: on_message,
           metadata: metadata,
           auto_approve_requests: true,
           turn_context: turn_context
         } = request,
         id,
         params
       ) do
    case tool_request_user_input_approval_answers(params) do
      {:ok, answers, decision} ->
        Protocol.send_message(port, %{"id" => id, "result" => %{"answers" => answers}})

        ObsLogger.emit(
          :info,
          :codex_approval_requested,
          EventFields.turn(turn_context, %{
            payload_summary: EventFields.stream_summary(payload),
            policy_action: "auto_approved"
          })
        )

        Messages.emit(
          on_message,
          :approval_auto_approved,
          %{payload: payload, raw: payload_string, decision: decision},
          metadata
        )

        :approved

      :error ->
        reply_with_non_interactive_tool_input_answer(
          request,
          id,
          params
        )
    end
  end

  defp maybe_auto_answer_tool_request_user_input(
         request,
         id,
         params
       ) do
    reply_with_non_interactive_tool_input_answer(
      request,
      id,
      params
    )
  end

  defp tool_request_user_input_approval_answers(%{"questions" => questions}) when is_list(questions) do
    answers =
      Enum.reduce_while(questions, %{}, fn question, acc ->
        case tool_request_user_input_approval_answer(question) do
          {:ok, question_id, answer_label} ->
            {:cont, Map.put(acc, question_id, %{"answers" => [answer_label]})}

          :error ->
            {:halt, :error}
        end
      end)

    case answers do
      :error -> :error
      answer_map when map_size(answer_map) > 0 -> {:ok, answer_map, "Approve this Session"}
      _answers -> :error
    end
  end

  defp tool_request_user_input_approval_answers(_params), do: :error

  defp reply_with_non_interactive_tool_input_answer(
         %{
           port: port,
           payload: payload,
           payload_string: payload_string,
           on_message: on_message,
           metadata: metadata,
           turn_context: turn_context
         },
         id,
         params
       ) do
    case tool_request_user_input_unavailable_answers(params) do
      {:ok, answers} ->
        Protocol.send_message(port, %{"id" => id, "result" => %{"answers" => answers}})

        ObsLogger.emit(
          :warning,
          :codex_input_required,
          EventFields.turn(turn_context, %{
            payload_summary: EventFields.stream_summary(payload),
            policy_action: "auto_answered"
          })
        )

        Messages.emit(
          on_message,
          :tool_input_auto_answered,
          %{payload: payload, raw: payload_string, answer: @non_interactive_tool_input_answer},
          metadata
        )

        :approved

      :error ->
        :input_required
    end
  end

  defp tool_request_user_input_unavailable_answers(%{"questions" => questions}) when is_list(questions) do
    answers =
      Enum.reduce_while(questions, %{}, fn question, acc ->
        case tool_request_user_input_question_id(question) do
          {:ok, question_id} ->
            {:cont, Map.put(acc, question_id, %{"answers" => [@non_interactive_tool_input_answer]})}

          :error ->
            {:halt, :error}
        end
      end)

    case answers do
      :error -> :error
      answer_map when map_size(answer_map) > 0 -> {:ok, answer_map}
      _answers -> :error
    end
  end

  defp tool_request_user_input_unavailable_answers(_params), do: :error

  defp tool_request_user_input_question_id(%{"id" => question_id}) when is_binary(question_id),
    do: {:ok, question_id}

  defp tool_request_user_input_question_id(_question), do: :error

  defp tool_request_user_input_approval_answer(%{"id" => question_id, "options" => options})
       when is_binary(question_id) and is_list(options) do
    case tool_request_user_input_approval_option_label(options) do
      nil -> :error
      answer_label -> {:ok, question_id, answer_label}
    end
  end

  defp tool_request_user_input_approval_answer(_question), do: :error

  defp tool_request_user_input_approval_option_label(options) do
    options
    |> Enum.map(&tool_request_user_input_option_label/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      labels ->
        Enum.find(labels, &(&1 == "Approve this Session")) ||
          Enum.find(labels, &(&1 == "Approve Once")) ||
          Enum.find(labels, &approval_option_label?/1)
    end
  end

  defp tool_request_user_input_option_label(%{"label" => label}) when is_binary(label), do: label
  defp tool_request_user_input_option_label(_option), do: nil

  defp approval_option_label?(label) when is_binary(label) do
    normalized_label =
      label
      |> String.trim()
      |> String.downcase()

    String.starts_with?(normalized_label, "approve") or String.starts_with?(normalized_label, "allow")
  end

  defp tool_call_name(params) when is_map(params) do
    case Map.get(params, "tool") || Map.get(params, :tool) || Map.get(params, "name") || Map.get(params, :name) do
      name when is_binary(name) ->
        case String.trim(name) do
          "" -> nil
          trimmed -> trimmed
        end

      _name ->
        nil
    end
  end

  defp tool_call_name(_params), do: nil

  defp input_required_method?(method, payload) when is_binary(method) do
    method in [
      "turn/input_required",
      "turn/needs_input",
      "turn/need_input",
      "turn/request_input",
      "turn/request_response",
      "turn/provide_input",
      "turn/approval_required"
    ] || request_payload_requires_input?(payload)
  end

  defp request_payload_requires_input?(payload) do
    params = Map.get(payload, "params")
    needs_input_field?(payload) || needs_input_field?(params)
  end

  defp needs_input_field?(payload) when is_map(payload) do
    Map.get(payload, "requiresInput") == true or
      Map.get(payload, "needsInput") == true or
      Map.get(payload, "input_required") == true or
      Map.get(payload, "inputRequired") == true or
      Map.get(payload, "type") == "input_required" or
      Map.get(payload, "type") == "needs_input"
  end

  defp needs_input_field?(_payload), do: false
end
