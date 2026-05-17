defmodule SymphonyWorkerDaemon.CommandPolicy.Capabilities do
  @moduledoc false

  alias SymphonyWorkerDaemon.CommandPolicy.AllowedExecutables
  alias SymphonyWorkerDaemon.CommandPolicy.CapabilityContract

  @command_key CapabilityContract.command_key()
  @name_key CapabilityContract.name_key()
  @path_key CapabilityContract.path_key()

  @spec build(keyword()) :: [map()]
  def build(opts) when is_list(opts) do
    if Keyword.get(opts, :allow_any_executable?, false) do
      [CapabilityContract.executable_policy_any()]
    else
      opts
      |> Keyword.get(:allowed_executables, [])
      |> capability_entries()
    end
  end

  defp capability_entries(entries) when is_list(entries) do
    Enum.flat_map(entries, fn
      %{@command_key => _command, @path_key => _path, @name_key => _name} = spec ->
        [CapabilityContract.executable_available(spec)]

      entry ->
        entry
        |> AllowedExecutables.normalize_entry()
        |> capability_entry()
    end)
  end

  defp capability_entries(_entries), do: []

  defp capability_entry(nil), do: []

  defp capability_entry(command) do
    case AllowedExecutables.resolve(command) do
      {:ok, spec} -> [CapabilityContract.executable_available(spec)]
      {:error, _reason} -> [CapabilityContract.executable_unavailable(command)]
    end
  end
end
