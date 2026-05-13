defmodule SymphonyWorkerDaemon.CommandPolicy.Capabilities do
  @moduledoc false

  alias SymphonyWorkerDaemon.CommandPolicy.AllowedExecutables

  @spec build(keyword()) :: [map()]
  def build(opts) when is_list(opts) do
    if Keyword.get(opts, :allow_any_executable?, false) do
      [%{"kind" => "executable_policy", "scope" => "any", "available" => true}]
    else
      opts
      |> Keyword.get(:allowed_executables, [])
      |> capability_entries()
    end
  end

  defp capability_entries(entries) when is_list(entries) do
    Enum.flat_map(entries, fn
      %{"command" => _command, "path" => _path, "name" => _name} = spec ->
        [Map.merge(%{"kind" => "executable", "available" => true}, spec)]

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
      {:ok, spec} -> [Map.merge(%{"kind" => "executable", "available" => true}, spec)]
      {:error, _reason} -> [%{"kind" => "executable", "command" => command, "name" => Path.basename(command), "available" => false}]
    end
  end
end
