defimpl SymphonyElixir.Agent.DynamicTool.ErrorProjector, for: SymphonyElixir.Repo.Error do
  alias SymphonyElixir.Agent.DynamicTool.ErrorProjector.Payload

  def project(error) do
    {:ok,
     Payload.local_error(
       error.operation,
       error.code,
       error.message,
       error.path,
       error.exit_code,
       error.retryable?,
       error.details
     )}
  end
end
