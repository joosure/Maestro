defmodule SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.Payload do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.{Access, Text}

  @spec unwrap_message_payload(term()) :: term()
  def unwrap_message_payload(%{} = message) do
    cond do
      is_binary(Access.map_value(message, ["method", :method])) -> message
      is_binary(Access.map_value(message, ["session_id", :session_id])) -> message
      is_binary(Access.map_value(message, ["reason", :reason])) -> message
      true -> Access.map_value(message, ["payload", :payload]) || message
    end
  end

  def unwrap_message_payload(message), do: message

  @spec extract_command(term()) :: String.t() | nil
  def extract_command(payload) do
    payload
    |> Access.map_path(["params", "parsedCmd"])
    |> command_from_payload(payload)
    |> normalize_command()
  end

  @spec normalize_command(term()) :: String.t() | nil
  def normalize_command(%{} = command) do
    binary_command =
      Access.map_value(command, ["parsedCmd", :parsedCmd, "command", :command, "cmd", :cmd])

    args = Access.map_value(command, ["args", :args, "argv", :argv])

    if is_binary(binary_command) and is_list(args) do
      normalize_command([binary_command | args])
    else
      normalize_command(binary_command || args)
    end
  end

  def normalize_command(command) when is_binary(command), do: Text.inline_text(command)

  def normalize_command(command) when is_list(command) do
    if Enum.all?(command, &is_binary/1) do
      command
      |> Enum.join(" ")
      |> Text.inline_text()
    else
      nil
    end
  end

  def normalize_command(_command), do: nil

  @spec dynamic_tool_name(term()) :: String.t() | nil
  def dynamic_tool_name(payload) do
    Access.map_path(payload, ["params", "tool"]) ||
      Access.map_path(payload, ["params", "name"]) ||
      Access.map_path(payload, [:params, :tool]) ||
      Access.map_path(payload, [:params, :name])
  end

  @spec wrapper_payload_type(term()) :: term()
  def wrapper_payload_type(payload) do
    Access.map_path(payload, ["params", "msg", "payload", "type"]) ||
      Access.map_path(payload, [:params, :msg, :payload, :type])
  end

  defp command_from_payload(nil, payload) do
    Access.map_path(payload, ["params", "command"]) ||
      Access.map_path(payload, ["params", "cmd"]) ||
      Access.map_path(payload, ["params", "argv"]) ||
      Access.map_path(payload, ["params", "args"])
  end

  defp command_from_payload(command, _payload), do: command
end
