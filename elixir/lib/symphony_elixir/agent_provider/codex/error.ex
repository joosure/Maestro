defmodule SymphonyElixir.AgentProvider.Codex.Error do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Error
  alias SymphonyElixir.Observability.Redaction

  @provider "codex"

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
  defp classify(:response_timeout, _operation), do: {:agent_provider_response_timeout, true}
  defp classify({:turn_input_required, _payload}, _operation), do: {:agent_provider_input_required, false}
  defp classify({:approval_required, _payload}, _operation), do: {:agent_provider_input_required, false}
  defp classify({:turn_cancelled, _payload}, _operation), do: {:agent_provider_cancelled, false}
  defp classify({:turn_failed, _payload}, _operation), do: {:agent_provider_turn_failed, false}
  defp classify({:codex_error, _payload}, _operation), do: {:agent_provider_turn_failed, false}
  defp classify({:response_error, _payload}, :run_turn), do: {:agent_provider_turn_failed, false}
  defp classify({:port_exit, _status}, _operation), do: {:agent_provider_command_exit, true}
  defp classify(:bash_not_found, _operation), do: {:agent_provider_command_missing, false}
  defp classify({:command_not_found, _command}, _operation), do: {:agent_provider_command_missing, false}
  defp classify({:invalid_command, _command}, _operation), do: {:agent_provider_command_invalid, false}
  defp classify({:invalid_command_argv, _argv}, _operation), do: {:agent_provider_command_invalid, false}
  defp classify({:unsafe_turn_sandbox_policy, _reason}, _operation), do: {:agent_provider_config_invalid, false}
  defp classify({:unsupported_agent_provider_options, _provider, _options}, _operation), do: {:agent_provider_config_invalid, false}
  defp classify({:invalid_workspace_cwd, _reason}, _operation), do: {:agent_provider_start_failed, false}
  defp classify({:invalid_workspace_cwd, _reason, _path}, _operation), do: {:agent_provider_start_failed, false}
  defp classify({:invalid_workspace_cwd, _reason, _path, _root}, _operation), do: {:agent_provider_start_failed, false}
  defp classify({:invalid_thread_payload, _payload}, _operation), do: {:agent_provider_start_failed, false}
  defp classify({:response_error, _payload}, :start_session), do: {:agent_provider_start_failed, false}
  defp classify(_reason, :start_session), do: {:agent_provider_start_failed, false}
  defp classify(_reason, :stop_session), do: {:agent_provider_cleanup_failed, false}
  defp classify(_reason, _operation), do: {:agent_provider_turn_failed, false}

  defp message(:turn_timeout, _code), do: "Codex turn timed out"
  defp message(:stall_timeout, _code), do: "Codex turn stalled"
  defp message(:response_timeout, _code), do: "Codex app-server response timed out"
  defp message({:turn_input_required, _payload}, _code), do: "Codex requested manual input"
  defp message({:approval_required, _payload}, _code), do: "Codex requested manual approval"
  defp message({:turn_cancelled, _payload}, _code), do: "Codex turn was cancelled"
  defp message({:turn_failed, _payload}, _code), do: "Codex turn failed"
  defp message({:codex_error, _payload}, _code), do: "Codex returned an error"
  defp message({:response_error, _payload}, :agent_provider_turn_failed), do: "Codex turn response failed"
  defp message({:response_error, _payload}, :agent_provider_start_failed), do: "Codex session startup response failed"
  defp message({:port_exit, status}, _code), do: "Codex app-server exited with status #{inspect(status)}"
  defp message(:bash_not_found, _code), do: "Codex command shell was not found"
  defp message({:command_not_found, command}, _code), do: "Codex command was not found: #{Redaction.summarize(command, 128)}"
  defp message({:invalid_command, _command}, _code), do: "Codex command configuration is invalid"
  defp message({:invalid_command_argv, _argv}, _code), do: "Codex command argv configuration is invalid"
  defp message({:unsafe_turn_sandbox_policy, _reason}, _code), do: "Codex turn sandbox policy is invalid"
  defp message({:invalid_workspace_cwd, _reason}, _code), do: "Codex workspace is invalid"
  defp message({:invalid_workspace_cwd, _reason, _path}, _code), do: "Codex workspace is invalid"
  defp message({:invalid_workspace_cwd, _reason, _path, _root}, _code), do: "Codex workspace is invalid"
  defp message({:invalid_thread_payload, _payload}, _code), do: "Codex thread startup payload was invalid"
  defp message(reason, _code), do: "Codex provider failure: #{Redaction.summarize(reason, 128)}"

  defp details({:port_exit, status}), do: %{exit_status: status}
  defp details({:command_not_found, command}), do: %{command_summary: Redaction.summarize(command, 256)}
  defp details({:invalid_command, command}), do: %{command_summary: Redaction.summarize(command, 256)}
  defp details({:invalid_command_argv, argv}), do: %{command_argv_summary: Redaction.summarize(argv, 256)}
  defp details(reason), do: %{reason_summary: Redaction.summarize(reason, 256)}
end
