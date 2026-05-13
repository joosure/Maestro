defmodule SymphonyElixir.AgentProvider.Codex.AppServer.Protocol do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.Handle

  @spec send_message(term(), map()) :: :ok | {:error, term()}
  def send_message(port, message) when is_map(message) do
    line = Jason.encode!(message) <> "\n"

    case Handle.command(port, line) do
      true -> :ok
      false -> {:error, :send_message_failed}
    end
  end
end
