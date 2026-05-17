defmodule SymphonyElixir.Tracker.Linear.Errors do
  @moduledoc false

  alias SymphonyElixir.Tracker.Error
  alias SymphonyElixir.Tracker.Kinds

  @provider_kind Kinds.linear()
  @retryable_http_statuses [408, 429, 500, 502, 503, 504]

  @spec normalize(atom(), term()) :: Error.t()
  def normalize(operation, %Error{} = error) do
    %Error{
      error
      | provider: if(error.provider in [nil, "", "unknown"], do: @provider_kind, else: error.provider),
        operation: operation
    }
  end

  def normalize(operation, :missing_linear_api_token) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :missing_credentials,
      message: "Linear API key is required.",
      details: %{source_reason: :missing_linear_api_token}
    })
  end

  def normalize(operation, :missing_linear_project_slug) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :missing_project_reference,
      message: "Linear project slug is required.",
      details: %{source_reason: :missing_linear_project_slug}
    })
  end

  def normalize(operation, :missing_linear_viewer_identity) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :invalid_configuration,
      message: "Linear viewer identity could not be resolved for assignee `me`.",
      details: %{source_reason: :missing_linear_viewer_identity}
    })
  end

  def normalize(operation, {:linear_api_status, status}) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :http_status,
      message: "Linear request failed with HTTP #{status}.",
      retryable?: status in @retryable_http_statuses,
      details: %{status: status, source_reason: {:linear_api_status, status}}
    })
  end

  def normalize(operation, {:linear_api_request, reason}) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :request_failed,
      message: "Linear request failed before receiving a successful response.",
      retryable?: true,
      details: %{reason: reason, source_reason: {:linear_api_request, reason}}
    })
  end

  def normalize(operation, {:linear_provider_errors, errors}) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :invalid_response,
      message: "Linear GraphQL returned errors.",
      details: %{errors: errors, source_reason: {:linear_provider_errors, errors}}
    })
  end

  def normalize(operation, reason)
      when reason in [:linear_unknown_payload, :linear_missing_end_cursor] do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :invalid_response,
      message: "Linear returned an unexpected payload.",
      details: %{source_reason: reason}
    })
  end

  def normalize(operation, reason)
      when reason in [:comment_create_failed, :issue_update_failed] do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :write_failed,
      message: "Linear write operation did not complete successfully.",
      details: %{source_reason: reason}
    })
  end

  def normalize(operation, reason) do
    Error.new(%{
      provider: @provider_kind,
      operation: operation,
      code: :unknown,
      message: "Linear request failed.",
      details: %{source_reason: reason}
    })
  end
end
