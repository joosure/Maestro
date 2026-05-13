defmodule SymphonyElixir.AgentProvider.ClaudeCode.Error do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Error
  alias SymphonyElixir.Observability.Redaction

  @provider "claude_code"

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
  defp classify(:port_closed, _operation), do: {:agent_provider_command_exit, true}
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
  defp classify({:claude_result_error, _payload}, _operation), do: {:agent_provider_turn_failed, false}
  defp classify({:response_error, _payload}, _operation), do: {:agent_provider_turn_failed, false}
  defp classify({:claude_code_tooling_failed, _reason}, :prepare_workspace), do: {:agent_provider_config_invalid, false}
  defp classify(_reason, :start_session), do: {:agent_provider_start_failed, false}
  defp classify(_reason, :stop_session), do: {:agent_provider_cleanup_failed, false}
  defp classify(_reason, :prepare_workspace), do: {:agent_provider_config_invalid, false}
  defp classify(_reason, _operation), do: {:agent_provider_turn_failed, false}

  defp message(:turn_timeout, _code), do: "Claude Code turn timed out"
  defp message(:turn_start_timeout, _code), do: "Claude Code did not produce initial output before read timeout"
  defp message(:stall_timeout, _code), do: "Claude Code turn stalled"
  defp message(:port_closed, _code), do: "Claude Code process closed before the turn completed"
  defp message(:bash_not_found, _code), do: "Claude Code command shell was not found"
  defp message({:command_not_found, command}, _code), do: "Claude Code command was not found: #{Redaction.summarize(command, 128)}"
  defp message({:invalid_command, _command}, _code), do: "Claude Code command configuration is invalid"
  defp message({:invalid_command_argv, _argv}, _code), do: "Claude Code command argv configuration is invalid"

  defp message(:dynamic_tool_bridge_http_port_unavailable, _code),
    do: "Claude Code MCP dynamic-tool bridge requires Symphony to run with an HTTP server port when Dynamic Tools are enabled"

  defp message({:remote_unsupported, _worker_host}, _code), do: "Claude Code provider does not support remote workers"
  defp message({:port_exit, status}, _code), do: "Claude Code process exited with status #{inspect(status)}"
  defp message({:claude_result_error, _payload}, _code), do: "Claude Code returned an unsuccessful result"
  defp message({:claude_code_tooling_failed, _reason}, _code), do: "Claude Code workspace tooling could not be prepared"
  defp message({:invalid_workspace_cwd, _reason}, _code), do: "Claude Code workspace is invalid"
  defp message({:invalid_workspace_cwd, _reason, _path}, _code), do: "Claude Code workspace is invalid"
  defp message({:invalid_workspace_cwd, _reason, _path, _root}, _code), do: "Claude Code workspace is invalid"
  defp message(reason, _code), do: "Claude Code provider failure: #{Redaction.summarize(reason, 128)}"

  defp details({:port_exit, status}), do: %{exit_status: status}
  defp details({:command_not_found, command}), do: %{command_summary: Redaction.summarize(command, 256)}
  defp details({:invalid_command, command}), do: %{command_summary: Redaction.summarize(command, 256)}
  defp details({:invalid_command_argv, argv}), do: %{command_argv_summary: Redaction.summarize(argv, 256)}
  defp details({:remote_unsupported, worker_host}), do: %{worker_host: worker_host}

  defp details(:dynamic_tool_bridge_http_port_unavailable) do
    %{
      required_option: "--port",
      required_runtime: "symphony_http_server",
      provider_requirement: "claude_code_mcp_dynamic_tools",
      condition: "tool_context_has_tools",
      workflow_scoped: false
    }
  end

  defp details(reason), do: %{reason_summary: Redaction.summarize(reason, 256)}
end
