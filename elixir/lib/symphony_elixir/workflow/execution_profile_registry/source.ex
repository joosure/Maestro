defmodule SymphonyElixir.Workflow.ExecutionProfileRegistry.Source do
  @moduledoc false

  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Entry
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.EntryNormalizer
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Values

  @env_key :workflow_execution_profiles

  @spec fetch_entries() :: {:ok, [Entry.t()]} | {:error, term()}
  def fetch_entries do
    with {:ok, entries} <-
           :symphony_elixir
           |> Application.get_env(@env_key, [])
           |> expand_raw_entries()
           |> EntryNormalizer.normalize_entries(),
         :ok <- validate_no_duplicate_entries(entries) do
      {:ok, entries}
    end
  end

  @spec validate_registry() :: :ok | {:error, term()}
  def validate_registry do
    case fetch_entries() do
      {:ok, _entries} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp expand_raw_entries([]), do: []

  defp expand_raw_entries(raw_entries) when is_list(raw_entries) do
    if Values.registry_entry_pair_list?(raw_entries) do
      [raw_entries]
    else
      Enum.flat_map(raw_entries, &expand_raw_entry/1)
    end
  end

  defp expand_raw_entries(nil), do: []
  defp expand_raw_entries(raw_entry), do: expand_raw_entry(raw_entry)

  defp expand_raw_entry(module) when is_atom(module) do
    Code.ensure_loaded(module)

    if function_exported?(module, :execution_profile_registry_entries, 0) do
      module.execution_profile_registry_entries()
      |> List.wrap()
    else
      [module]
    end
  end

  defp expand_raw_entry(raw_entry), do: [raw_entry]

  defp validate_no_duplicate_entries(entries) when is_list(entries) do
    entries
    |> Enum.flat_map(fn %Entry{} = entry ->
      Enum.map(entry.profile_versions, &{entry.name, entry.profile_kind, &1})
    end)
    |> Enum.reduce_while(MapSet.new(), fn key, seen ->
      if MapSet.member?(seen, key) do
        {:halt, {:error, {:invalid_workflow_execution_profile_registry, {:duplicate_registry_entry, key}}}}
      else
        {:cont, MapSet.put(seen, key)}
      end
    end)
    |> case do
      %MapSet{} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
