defmodule SymphonyWorkerDaemon.Session.Server.Request do
  @moduledoc false

  alias SymphonyWorkerDaemon.Protocol.Fields, as: ProtocolFields

  @workspace_key ProtocolFields.workspace()
  @command_key ProtocolFields.command()
  @mode_key ProtocolFields.mode()

  @spec workspace(map()) :: map()
  def workspace(%{@workspace_key => workspace}), do: workspace
  def workspace(_request), do: %{}

  @spec command(map()) :: map()
  def command(%{@command_key => command}) when is_map(command), do: command
  def command(_request), do: %{@mode_key => "unset"}
end
