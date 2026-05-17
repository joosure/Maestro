defmodule SymphonyElixir.Tracker.Tapd.Client.Errors do
  @moduledoc false

  alias SymphonyElixir.Tracker.Error
  alias SymphonyElixir.Tracker.Kinds

  @provider_kind Kinds.tapd()
  @retryable_http_statuses [408, 429, 500, 502, 503, 504]

  @spec map_result(term(), atom()) :: term()
  def map_result({:error, reason}, operation), do: {:error, normalize(operation, reason)}
  def map_result(result, _operation), do: result

  @spec normalize(atom(), term()) :: Error.t()
  def normalize(operation, %Error{} = error) do
    %Error{
      error
      | provider: if(error.provider in [nil, "", "unknown"], do: @provider_kind, else: error.provider),
        operation: operation
    }
  end

  def normalize(operation, {:tapd_http_status, status, body}) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :http_status,
      message: "TAPD request failed with HTTP #{status}.",
      retryable?: status in @retryable_http_statuses,
      details: %{status: status, body: body, source_reason: {:tapd_http_status, status, body}}
    })
  end

  def normalize(operation, {:tapd_request, reason}) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :request_failed,
      message: "TAPD request failed before a successful response was received.",
      retryable?: true,
      details: %{reason: reason, source_reason: {:tapd_request, reason}}
    })
  end

  def normalize(operation, {:tapd_business_error, body}) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :business_error,
      message: "TAPD returned a business error response.",
      details: %{body: body, source_reason: {:tapd_business_error, body}}
    })
  end

  def normalize(operation, {:tapd_workflow_lookup_failed, workitem_type_id, type, nested_reason}) do
    nested_error = normalize(operation, nested_reason)

    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :workflow_lookup_failed,
      message: "TAPD workflow lookup failed.",
      retryable?: Error.retryable?(nested_error),
      details: %{
        workitem_type_id: workitem_type_id,
        workflow_type: type,
        nested_error: nested_error,
        source_reason: {:tapd_workflow_lookup_failed, workitem_type_id, type, nested_reason}
      }
    })
  end

  def normalize(operation, reason)
      when reason in [:missing_tapd_credentials, :missing_tapd_api_user, :missing_tapd_api_secret] do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :missing_credentials,
      message: "TAPD credentials are required.",
      details: %{source_reason: reason}
    })
  end

  def normalize(operation, :missing_tapd_workspace_id) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :missing_project_reference,
      message: "TAPD workspace id is required.",
      details: %{source_reason: :missing_tapd_workspace_id}
    })
  end

  def normalize(operation, :missing_tapd_active_states) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :invalid_configuration,
      message: "TAPD active states are required.",
      details: %{source_reason: :missing_tapd_active_states}
    })
  end

  def normalize(operation, {:unexpected_tapd_payload, path, body}) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :invalid_response,
      message: "TAPD returned an unexpected payload for #{path}.",
      details: %{path: path, body: body, source_reason: {:unexpected_tapd_payload, path, body}}
    })
  end

  def normalize(operation, {:tapd_mismatched_workitem_type_ids, details}) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :tapd_mismatched_workitem_type_ids,
      message: "Observed TAPD workitem types do not match the configured workflow terminal states.",
      details: %{details: details, source_reason: {:tapd_mismatched_workitem_type_ids, details}}
    })
  end

  def normalize(operation, {:tapd_parallel_workitem_workflow, details}) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :tapd_parallel_workitem_workflow,
      message: "Parallel TAPD workflows are not supported for the requested operation.",
      details: %{details: details, source_reason: {:tapd_parallel_workitem_workflow, details}}
    })
  end

  def normalize(operation, reason)
      when reason in [
             :workspace_id_must_not_be_supplied,
             :invalid_tapd_params,
             :unsupported_tapd_method,
             :unsupported_tapd_path,
             :conflicting_tapd_workitem_type_scope
           ] do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :invalid_configuration,
      message: "TAPD request or configuration is invalid.",
      details: %{source_reason: reason}
    })
  end

  def normalize(operation, reason) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :unknown,
      message: "TAPD request failed.",
      details: %{source_reason: reason}
    })
  end

  @spec classify_story_update_error(term(), String.t(), String.t()) :: term()
  def classify_story_update_error(reason, story_id, target_status)
      when is_binary(story_id) and is_binary(target_status) do
    normalize_story_update_error(reason, story_id, target_status)
  end

  defp normalize_story_update_error(
         %Error{code: :business_error, details: %{body: body}} = error,
         story_id,
         target_status
       ) do
    message = extract_error_message(body)

    if parallel_workflow_message?(message) do
      Error.new(%{
        provider: @provider_kind,
        operation: :update_issue_state,
        code: :tapd_story_parallel_workflow_error,
        message: message || "TAPD rejected the state transition for a parallel workflow story.",
        details: %{
          story_id: story_id,
          target_status: target_status,
          message: message,
          body: body,
          source_reason: error
        }
      })
    else
      Error.new(%{
        provider: @provider_kind,
        operation: :update_issue_state,
        code: :tapd_story_workflow_error,
        message: message || "TAPD rejected the requested story state transition.",
        details: %{
          story_id: story_id,
          target_status: target_status,
          message: message,
          body: body,
          source_reason: error
        }
      })
    end
  end

  defp normalize_story_update_error(%Error{} = error, _story_id, _target_status), do: error
  defp normalize_story_update_error(reason, _story_id, _target_status), do: reason

  defp extract_error_message(%{} = body) do
    body = normalize_keys_to_strings(body)

    cond do
      is_binary(body["info"]) and String.trim(body["info"]) != "" ->
        String.trim(body["info"])

      is_binary(body["message"]) and String.trim(body["message"]) != "" ->
        String.trim(body["message"])

      is_binary(body["msg"]) and String.trim(body["msg"]) != "" ->
        String.trim(body["msg"])

      is_map(body["error"]) ->
        extract_error_message(body["error"])

      is_binary(body["error"]) and String.trim(body["error"]) != "" ->
        String.trim(body["error"])

      is_list(body["errors"]) ->
        Enum.find_value(body["errors"], &extract_error_message/1)

      true ->
        nil
    end
  end

  defp extract_error_message(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp extract_error_message(_value), do: nil

  defp parallel_workflow_message?(nil), do: false

  defp parallel_workflow_message?(message) when is_binary(message) do
    normalized_message = String.downcase(message)

    Enum.any?(
      [
        "parallel workflow",
        "parallel step",
        "并行工作流",
        "并行流程",
        "并行节点",
        "节点完成",
        "进行中节点",
        "工作流节点"
      ],
      &String.contains?(normalized_message, &1)
    )
  end

  defp normalize_keys_to_strings(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
