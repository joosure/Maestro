defmodule SymphonyElixir.Workflow.Extension.ToolResultRecorder.Registry.Collector do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.Registry, as: ExtensionRegistry
  alias SymphonyElixir.Workflow.Extension.ToolResultRecorder.Registry.Error

  @spec recorder_specs(keyword()) :: {:ok, [map()]} | {:error, map()}
  def recorder_specs(opts) do
    with {:ok, base_specs} <- base_recorder_specs(opts),
         {:ok, extra_modules} <- module_list_option(opts, :extra_recorder_modules, :extra_recorder_modules_not_list) do
      extra_specs = sourced_modules(extra_modules, :extra_opts)

      {:ok, base_specs ++ extra_specs}
    end
  end

  defp base_recorder_specs(opts) do
    if Keyword.has_key?(opts, :recorder_modules) do
      with {:ok, modules} <- module_list_option(opts, :recorder_modules, :recorder_modules_not_list) do
        {:ok, sourced_modules(modules, :opts)}
      end
    else
      extension_recorder_specs(opts)
    end
  end

  defp extension_recorder_specs(opts) do
    opts
    |> extension_registry_opts()
    |> ExtensionRegistry.entries()
    |> case do
      {:ok, extension_entries} -> collect_extension_recorder_specs(extension_entries)
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect_extension_recorder_specs(extension_entries) do
    Enum.reduce_while(extension_entries, {:ok, []}, fn extension_entry, {:ok, specs} ->
      case recorder_modules_from_extension(extension_entry) do
        {:ok, modules} ->
          source = {:extension, extension_entry.id, extension_entry.module}
          {:cont, {:ok, specs ++ sourced_modules(modules, source)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp recorder_modules_from_extension(extension_entry) do
    module = extension_entry.module

    if function_exported?(module, :tool_result_recorders, 0) do
      case safe_call(module, :tool_result_recorders, []) do
        {:ok, modules} when is_list(modules) ->
          {:ok, modules}

        {:ok, modules} ->
          {:error,
           Error.invalid_source(module, :tool_result_recorders_not_list,
             extension_id: extension_entry.id,
             value_type: Diagnostics.type_name(modules)
           )}

        {:error, callback_error} ->
          {:error,
           Error.invalid_source(module, :tool_result_recorders_failed,
             extension_id: extension_entry.id,
             callback_error: callback_error
           )}
      end
    else
      {:ok, []}
    end
  end

  defp module_list_option(opts, key, reason) do
    value = Keyword.get(opts, key, [])

    if is_list(value) do
      {:ok, value}
    else
      {:error, Error.invalid(reason, value_type: Diagnostics.type_name(value))}
    end
  end

  defp sourced_modules(modules, source), do: Enum.map(modules, &%{module: &1, source: source})

  defp extension_registry_opts(opts) do
    opts
    |> Keyword.take([:entries, :extra_entries, :sources, :extra_sources, :source_opts])
    |> case do
      [] -> []
      registry_opts -> registry_opts
    end
  end

  defp safe_call(module, callback, args) do
    {:ok, apply(module, callback, args)}
  rescue
    error ->
      {:error, Diagnostics.exception(error)}
  catch
    kind, reason ->
      {:error, Diagnostics.caught(kind, reason)}
  end
end
