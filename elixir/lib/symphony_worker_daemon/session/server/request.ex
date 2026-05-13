defmodule SymphonyWorkerDaemon.Session.Server.Request do
  @moduledoc false

  @spec workspace(map()) :: map()
  def workspace(%{"workspace" => workspace}), do: workspace
  def workspace(_request), do: %{}

  @spec command(map()) :: map()
  def command(%{"command" => command}) when is_map(command), do: command
  def command(_request), do: %{"mode" => "unset"}
end
