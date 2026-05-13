defmodule SymphonyElixir.AgentProvider.OpenCode.Error do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Error
  alias SymphonyElixir.Observability.Redaction

  @provider "opencode"

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
  defp classify(:stall_timeout, _operation), do: {:agent_provider_timeout, true}
  defp classify(:bash_not_found, _operation), do: {:agent_provider_command_missing, false}
  defp classify({:command_not_found, _command}, _operation), do: {:agent_provider_command_missing, false}
  defp classify({:invalid_command, _command}, _operation), do: {:agent_provider_command_invalid, false}
  defp classify({:invalid_command_argv, _argv}, _operation), do: {:agent_provider_command_invalid, false}
  defp classify({:unsupported_agent_provider_options, _provider, _options}, _operation), do: {:agent_provider_config_invalid, false}
  defp classify(:dynamic_tool_bridge_http_port_unavailable, _operation), do: {:agent_provider_config_invalid, false}
  defp classify({:invalid_workspace_cwd, _reason}, _operation), do: {:agent_provider_start_failed, false}
  defp classify({:invalid_workspace_cwd, _reason, _path}, _operation), do: {:agent_provider_start_failed, false}
  defp classify({:invalid_workspace_cwd, _reason, _path, _root}, _operation), do: {:agent_provider_start_failed, false}
  defp classify({:remote_unsupported, _worker_host}, _operation), do: {:agent_provider_remote_unsupported, false}
  defp classify({:port_exit, _status}, _operation), do: {:agent_provider_command_exit, true}
  defp classify({:server_start_port_exit, _details}, _operation), do: {:agent_provider_command_exit, true}
  defp classify({:server_start_timeout, _details}, _operation), do: {:agent_provider_timeout, true}
  defp classify({:healthcheck_timeout, _details}, _operation), do: {:agent_provider_response_timeout, true}
  defp classify({:healthcheck_failed, _details}, _operation), do: {:agent_provider_start_failed, true}
  defp classify({:session_create_timeout, _details}, _operation), do: {:agent_provider_response_timeout, true}
  defp classify({:session_create_http_error, _details}, _operation), do: {:agent_provider_start_failed, false}
  defp classify({:session_create_transport_error, _details}, _operation), do: {:agent_provider_start_failed, true}
  defp classify({:message_post_timeout, _details}, _operation), do: {:agent_provider_response_timeout, true}
  defp classify({:message_post_http_error, _details}, _operation), do: {:agent_provider_turn_failed, false}
  defp classify({:message_post_transport_error, _details}, _operation), do: {:agent_provider_turn_failed, true}
  defp classify({:event_stream_timeout, _details}, _operation), do: {:agent_provider_response_timeout, true}
  defp classify({:event_stream_failed, _details}, _operation), do: {:agent_provider_turn_failed, true}
  defp classify({:turn_input_required, _payload}, _operation), do: {:agent_provider_input_required, false}
  defp classify({:session_error, _payload}, _operation), do: {:agent_provider_turn_failed, false}
  defp classify({:message_error, _payload}, _operation), do: {:agent_provider_turn_failed, false}
  defp classify({:opencode_tooling_failed, _reason}, :prepare_workspace), do: {:agent_provider_config_invalid, false}
  defp classify(_reason, :start_session), do: {:agent_provider_start_failed, false}
  defp classify(_reason, :stop_session), do: {:agent_provider_cleanup_failed, false}
  defp classify(_reason, :prepare_workspace), do: {:agent_provider_config_invalid, false}
  defp classify(_reason, _operation), do: {:agent_provider_turn_failed, false}

  defp message(:turn_timeout, _code), do: "OpenCode turn timed out"
  defp message(:stall_timeout, _code), do: "OpenCode turn stalled"
  defp message(:bash_not_found, _code), do: "OpenCode command shell was not found"
  defp message({:command_not_found, command}, _code), do: "OpenCode command was not found: #{Redaction.summarize(command, 128)}"
  defp message({:invalid_command, _command}, _code), do: "OpenCode command configuration is invalid"
  defp message({:invalid_command_argv, _argv}, _code), do: "OpenCode command argv configuration is invalid"

  defp message(:dynamic_tool_bridge_http_port_unavailable, _code),
    do: "OpenCode dynamic-tool bridge requires Symphony to run with an HTTP server port"

  defp message({:remote_unsupported, _worker_host}, _code), do: "OpenCode provider does not support remote workers"
  defp message({:port_exit, status}, _code), do: "OpenCode server exited with status #{inspect(status)}"
  defp message({:opencode_tooling_failed, _reason}, _code), do: "OpenCode workspace tooling could not be prepared"
  defp message({kind, details}, _code) when is_atom(kind) and is_map(details), do: Map.get(details, :message) || Map.get(details, "message") || "OpenCode provider failure"
  defp message(reason, _code), do: "OpenCode provider failure: #{Redaction.summarize(reason, 128)}"

  defp details({:port_exit, status}), do: %{exit_status: status}
  defp details({:command_not_found, command}), do: %{command_summary: Redaction.summarize(command, 256)}
  defp details({:invalid_command, command}), do: %{command_summary: Redaction.summarize(command, 256)}
  defp details({:invalid_command_argv, argv}), do: %{command_argv_summary: Redaction.summarize(argv, 256)}
  defp details({:remote_unsupported, worker_host}), do: %{worker_host: worker_host}
  defp details(:dynamic_tool_bridge_http_port_unavailable), do: %{required_option: "--port"}
  defp details({_kind, details}) when is_map(details), do: Redaction.redact(details)
  defp details(reason), do: %{reason_summary: Redaction.summarize(reason, 256)}
end
