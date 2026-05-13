defmodule SymphonyWorkerDaemon.CommandPolicy.Validation do
  @moduledoc false

  alias SymphonyWorkerDaemon.CommandPolicy.AllowedExecutables

  @spec executable_allowed?(String.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def executable_allowed?(command, resolved_path, opts) when is_binary(command) and is_binary(resolved_path) and is_list(opts) do
    case AllowedExecutables.allowed_specs(opts) do
      {:ok, []} ->
        {:error, {:command_not_allowlisted, safe_command(command)}}

      {:ok, specs} ->
        if Enum.any?(specs, &AllowedExecutables.matches?(&1, command, resolved_path)) do
          :ok
        else
          {:error, {:command_not_allowlisted, safe_command(command)}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp safe_command(command) when is_binary(command), do: %{command: command, name: Path.basename(command)}
end
