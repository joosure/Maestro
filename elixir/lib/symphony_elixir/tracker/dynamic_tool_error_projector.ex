defimpl SymphonyElixir.Agent.DynamicTool.ErrorProjector, for: SymphonyElixir.Tracker.Error do
  alias SymphonyElixir.Agent.DynamicTool.ErrorProjector.Payload

  def project(error) do
    {:ok,
     Payload.provider_error(
       error.provider,
       error.operation,
       error.code,
       error.message,
       error.retryable?,
       error.details
     )}
  end
end
