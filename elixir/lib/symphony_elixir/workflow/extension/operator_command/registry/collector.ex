defmodule SymphonyElixir.Workflow.Extension.OperatorCommand.Registry.Collector do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.OperatorCommand.Registry.Error
  alias SymphonyElixir.Workflow.Extension.Registry, as: ExtensionRegistry

  @spec command_specs(keyword()) :: {:ok, [map()]} | {:error, map()}
  def command_specs(opts) do
    with {:ok, base_specs} <- base_command_specs(opts),
         {:ok, extra_specs} <- command_module_specs(opts, :extra_command_modules, :extra_opts) do
      {:ok, base_specs ++ extra_specs}
    end
  end

  defp base_command_specs(opts) do
    if Keyword.has_key?(opts, :command_modules) do
      command_module_specs(opts, :command_modules, :opts)
    else
      extension_command_specs(opts)
    end
  end

  defp command_module_specs(opts, option, source) do
    case Keyword.get(opts, option, []) do
      modules when is_list(modules) ->
        {:ok, sourced_modules(modules, source)}

      value ->
        {:error, Error.invalid(:command_modules_not_list, option: option, value_type: Diagnostics.type_name(value))}
    end
  end

  defp extension_command_specs(opts) do
    opts
    |> extension_registry_opts()
    |> ExtensionRegistry.entries()
    |> case do
      {:ok, extension_entries} -> collect_extension_command_specs(extension_entries)
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect_extension_command_specs(extension_entries) do
    Enum.reduce_while(extension_entries, {:ok, []}, fn extension_entry, {:ok, specs} ->
      case command_modules_from_extension(extension_entry) do
        {:ok, modules} ->
          source = {:extension, extension_entry.id, extension_entry.module}
          {:cont, {:ok, specs ++ sourced_modules(modules, source)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp command_modules_from_extension(extension_entry) do
    module = extension_entry.module

    if function_exported?(module, :operator_commands, 0) do
      case safe_call(module, :operator_commands, []) do
        {:ok, modules} when is_list(modules) ->
          {:ok, modules}

        {:ok, modules} ->
          {:error,
           Error.invalid_source(module, :operator_commands_not_list,
             extension_id: extension_entry.id,
             value_type: Diagnostics.type_name(modules)
           )}

        {:error, callback_error} ->
          {:error,
           Error.invalid_source(module, :operator_commands_failed,
             extension_id: extension_entry.id,
             callback_error: callback_error
           )}
      end
    else
      {:ok, []}
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
