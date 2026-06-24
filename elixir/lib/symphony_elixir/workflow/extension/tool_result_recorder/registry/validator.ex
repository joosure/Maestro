defmodule SymphonyElixir.Workflow.Extension.ToolResultRecorder.Registry.Validator do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.ToolResultRecorder.Registry.Entry
  alias SymphonyElixir.Workflow.Extension.ToolResultRecorder.Registry.Error

  @spec unique_modules([map()]) :: :ok | {:error, map()}
  def unique_modules(specs) do
    duplicates =
      specs
      |> Enum.group_by(& &1.module)
      |> Enum.filter(fn {_module, specs} -> length(specs) > 1 end)
      |> Enum.map(fn {module, specs} ->
        %{module: inspect(module), sources: Enum.map(specs, &Error.source_diagnostic(&1.source))}
      end)

    case duplicates do
      [] -> :ok
      duplicates -> {:error, Error.invalid(:duplicate_tool_result_recorder_modules, duplicates: duplicates)}
    end
  end

  @spec unique_ids([Entry.t()]) :: :ok | {:error, map()}
  def unique_ids(entries) do
    duplicates =
      entries
      |> Enum.group_by(& &1.id)
      |> Enum.filter(fn {_id, entries} -> length(entries) > 1 end)
      |> Enum.map(fn {id, entries} -> %{id: id, entries: Enum.map(entries, &Entry.diagnostic/1)} end)

    case duplicates do
      [] -> :ok
      duplicates -> {:error, Error.invalid(:duplicate_tool_result_recorder_ids, duplicates: duplicates)}
    end
  end
end
