defimpl SymphonyElixir.Agent.DynamicTool.ErrorProjector, for: SymphonyElixir.RepoProvider.Error do
  alias SymphonyElixir.Agent.DynamicTool.ErrorProjector.Payload

  def project(error) do
    {:ok,
     Payload.provider_error(
       error.provider,
       error.operation,
       error.code,
       error.message,
       error.retryable?,
       error.details,
       exit_code: error.exit_code
     )}
  end
end
