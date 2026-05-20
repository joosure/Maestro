defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.Error do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Error
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.Config.ErrorFormatter
  alias SymphonyElixir.Observability.Redaction

  @provider Kinds.codebuddy_code()

  @spec normalize(term(), atom()) :: Error.t()
  def normalize(%Error{} = error, _operation), do: error

  def normalize(reason, operation) when is_atom(operation) do
    {code, retryable?} = classify(reason, operation)

    Error.new(%{
      provider: @provider,
      operation: operation,
      code: code,
      message: message(reason, code),
      retryable?: retryable?,
      details: details(reason)
    })
  end

  defp classify(:turn_timeout, _operation), do: {:agent_provider_timeout, true}
  defp classify(:turn_start_timeout, _operation), do: {:agent_provider_response_timeout, true}
  defp classify(:stall_timeout, _operation), do: {:agent_provider_timeout, true}
  defp classify(:response_timeout, _operation), do: {:agent_provider_response_timeout, true}
  defp classify(:port_closed, _operation), do: {:agent_provider_command_exit, true}
  defp classify(:bash_not_found, _operation), do: {:agent_provider_command_missing, false}
  defp classify({:command_not_found, _command}, _operation), do: {:agent_provider_command_missing, false}
  defp classify({:invalid_command, _command}, _operation), do: {:agent_provider_command_invalid, false}
  defp classify({:invalid_command_argv, _argv}, _operation), do: {:agent_provider_command_invalid, false}
  defp classify({:invalid_command_spec, _summary}, _operation), do: {:agent_provider_command_invalid, false}
  defp classify(%Ecto.Changeset{}, _operation), do: {:agent_provider_config_invalid, false}
  defp classify({:unsupported_agent_provider_options, _provider, _options}, _operation), do: {:agent_provider_config_invalid, false}
  defp classify({:unsupported_transport, _transport}, _operation), do: {:agent_provider_capability_unsupported, false}
  defp classify({:codebuddy_command_conflict, _flag}, _operation), do: {:agent_provider_config_invalid, false}
  defp classify({:invalid_workspace_cwd, _reason}, _operation), do: {:agent_provider_start_failed, false}
  defp classify({:invalid_workspace_cwd, _reason, _path}, _operation), do: {:agent_provider_start_failed, false}
  defp classify({:invalid_workspace_cwd, _reason, _path, _root}, _operation), do: {:agent_provider_start_failed, false}
  defp classify({:remote_unsupported, _worker_host}, _operation), do: {:agent_provider_remote_unsupported, false}
  defp classify({:port_exit, _status}, _operation), do: {:agent_provider_command_exit, true}
  defp classify({:codebuddy_acp_http_endpoint_timeout, _details}, _operation), do: {:agent_provider_response_timeout, true}
  defp classify({:codebuddy_acp_http_health_timeout, _details}, _operation), do: {:agent_provider_response_timeout, true}
  defp classify({:codebuddy_acp_http_connect_timeout, _details}, _operation), do: {:agent_provider_response_timeout, true}
  defp classify({:codebuddy_acp_http_transport_error, _details}, _operation), do: {:agent_provider_response_timeout, true}
  defp classify({:codebuddy_acp_http_error, _details}, _operation), do: {:agent_provider_turn_failed, false}
  defp classify({:codebuddy_acp_http_start_port_exit, _details}, _operation), do: {:agent_provider_command_exit, true}
  defp classify({:response_error, _payload}, _operation), do: {:agent_provider_turn_failed, false}
  defp classify({:turn_failed, _payload}, _operation), do: {:agent_provider_turn_failed, false}
  defp classify({:turn_cancelled, _payload}, _operation), do: {:agent_provider_cancelled, false}
  defp classify({:turn_input_required, _payload}, _operation), do: {:agent_provider_input_required, false}
  defp classify({:client_request_unsupported, _payload}, _operation), do: {:agent_provider_input_required, false}
  defp classify(:duplicate_terminal_event, _operation), do: {:agent_provider_turn_failed, false}
  defp classify(_reason, :start_session), do: {:agent_provider_start_failed, false}
  defp classify(_reason, :stop_session), do: {:agent_provider_cleanup_failed, false}
  defp classify(_reason, :prepare_workspace), do: {:agent_provider_config_invalid, false}
  defp classify(_reason, _operation), do: {:agent_provider_turn_failed, false}

  defp message(:turn_timeout, _code), do: "CodeBuddy Code turn timed out"
  defp message(:turn_start_timeout, _code), do: "CodeBuddy Code did not produce initial output before read timeout"
  defp message(:stall_timeout, _code), do: "CodeBuddy Code turn stalled"
  defp message(:response_timeout, _code), do: "CodeBuddy Code did not return the expected ACP response before timeout"
  defp message(:port_closed, _code), do: "CodeBuddy Code process closed before the turn completed"
  defp message(:bash_not_found, _code), do: "CodeBuddy Code command shell was not found"
  defp message({:command_not_found, command}, _code), do: "CodeBuddy Code command was not found: #{Redaction.summarize(command, 128)}"
  defp message({:invalid_command, _command}, _code), do: "CodeBuddy Code command configuration is invalid"
  defp message({:invalid_command_argv, _argv}, _code), do: "CodeBuddy Code command argv configuration is invalid"
  defp message(%Ecto.Changeset{}, _code), do: "CodeBuddy Code provider configuration is invalid"
  defp message({:unsupported_transport, transport}, _code), do: "CodeBuddy Code transport is unsupported: #{transport}"
  defp message({:codebuddy_command_conflict, flag}, _code), do: "CodeBuddy Code command conflicts with provider-owned flag #{flag}"
  defp message({:remote_unsupported, _worker_host}, _code), do: "CodeBuddy Code provider does not support remote workers"
  defp message({:port_exit, status}, _code), do: "CodeBuddy Code process exited with status #{inspect(status)}"
  defp message({:codebuddy_acp_http_endpoint_timeout, _details}, _code), do: "CodeBuddy Code did not announce its ACP HTTP endpoint before timeout"
  defp message({:codebuddy_acp_http_health_timeout, _details}, _code), do: "CodeBuddy Code ACP HTTP healthcheck timed out"
  defp message({:codebuddy_acp_http_connect_timeout, _details}, _code), do: "CodeBuddy Code ACP HTTP connect timed out"
  defp message({:codebuddy_acp_http_transport_error, _details}, _code), do: "CodeBuddy Code ACP HTTP transport failed"
  defp message({:codebuddy_acp_http_error, _details}, _code), do: "CodeBuddy Code ACP HTTP returned an unsuccessful response"
  defp message({:codebuddy_acp_http_start_port_exit, _details}, _code), do: "CodeBuddy Code process exited before ACP HTTP startup completed"
  defp message({:response_error, _payload}, _code), do: "CodeBuddy Code returned an ACP error response"
  defp message({:turn_failed, _payload}, _code), do: "CodeBuddy Code turn failed"
  defp message({:turn_cancelled, _payload}, _code), do: "CodeBuddy Code turn was cancelled"
  defp message({:turn_input_required, _payload}, _code), do: "CodeBuddy Code requires manual input or permission approval"
  defp message({:client_request_unsupported, _payload}, _code), do: "CodeBuddy Code requested an unsupported ACP client operation"
  defp message(:duplicate_terminal_event, _code), do: "CodeBuddy Code emitted duplicate terminal turn events"
  defp message(reason, _code), do: "CodeBuddy Code provider failure: #{Redaction.summarize(reason, 128)}"

  defp details({:port_exit, status}), do: %{exit_status: status}
  defp details({:command_not_found, command}), do: %{command_summary: Redaction.summarize(command, 256)}
  defp details({:invalid_command, command}), do: %{command_summary: Redaction.summarize(command, 256)}
  defp details({:invalid_command_argv, argv}), do: %{command_argv_summary: Redaction.summarize(argv, 256)}
  defp details(%Ecto.Changeset{} = changeset), do: %{validation_errors: ErrorFormatter.format(changeset)}
  defp details({:remote_unsupported, worker_host}), do: %{worker_host: worker_host}
  defp details({:unsupported_transport, transport}), do: %{transport: transport}
  defp details({:codebuddy_command_conflict, flag}), do: %{flag: flag}
  defp details(reason), do: %{reason_summary: Redaction.summarize(reason, 256)}
end
