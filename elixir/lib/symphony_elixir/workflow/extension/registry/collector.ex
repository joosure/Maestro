defmodule SymphonyElixir.Workflow.Extension.Registry.Collector do
  @moduledoc """
  Collects trusted workflow runtime-extension module specs.

  Collection turns function-level opts, production configuration, and trusted
  source callbacks into raw module/source specs. It does not normalize modules
  into registry entries or resolve duplicate identities.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.Registry.Config
  alias SymphonyElixir.Workflow.Extension.Registry.Entry
  alias SymphonyElixir.Workflow.Extension.Registry.Error
  alias SymphonyElixir.Workflow.Extension.Registry.Validator

  @type spec :: %{module: module(), source: Entry.source()}

  @spec collect(keyword()) :: {:ok, [spec()]} | {:error, map()}
  def collect(opts) do
    with {:ok, base_specs} <- base_entry_specs(opts),
         {:ok, extra_entry_specs} <- entry_module_specs(opts, :extra_entries, :extra_opts),
         {:ok, extra_source_specs} <- source_entry_specs_from_option(opts, :extra_sources, :extra_source) do
      {:ok, base_specs ++ extra_entry_specs ++ extra_source_specs}
    end
  end

  defp base_entry_specs(opts) do
    cond do
      Keyword.has_key?(opts, :entries) ->
        entry_module_specs(opts, :entries, :opts)

      Keyword.has_key?(opts, :sources) ->
        source_entry_specs_from_option(opts, :sources, :source)

      true ->
        configured_entry_specs(opts)
    end
  end

  defp configured_entry_specs(opts) do
    with {:ok, sources} <- Config.configured_sources(),
         {:ok, source_specs} <- source_entry_specs(sources, :source, opts) do
      {:ok, source_specs}
    end
  end

  defp entry_module_specs(opts, option, source) do
    case Keyword.get(opts, option, []) do
      modules when is_list(modules) ->
        {:ok, sourced_modules(modules, source)}

      value ->
        {:error, Error.invalid(:registry, :extension_modules_not_list, option: option, value_type: Diagnostics.type_atom(value))}
    end
  end

  defp source_entry_specs_from_option(opts, option, source_kind) do
    case Keyword.get(opts, option, []) do
      source_modules when is_list(source_modules) ->
        source_entry_specs(source_modules, source_kind, opts)

      value ->
        {:error, Error.invalid(:registry, :extension_sources_not_list, option: option, value_type: Diagnostics.type_atom(value))}
    end
  end

  defp source_entry_specs(source_modules, source_kind, opts) do
    source_modules
    |> Enum.reduce_while({:ok, []}, fn source_module, {:ok, specs} ->
      case extension_modules_from_source(source_module, opts) do
        {:ok, modules} -> {:cont, {:ok, specs ++ sourced_modules(modules, {source_kind, source_module})}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp extension_modules_from_source(source_module, opts) do
    source_opts = Keyword.get(opts, :source_opts, [])

    with :ok <- Validator.validate_source_module(source_module),
         {:ok, modules} <- call_source(source_module, source_opts),
         :ok <- Validator.validate_source_modules_list(source_module, modules) do
      {:ok, modules}
    end
  end

  defp call_source(source_module, source_opts) do
    {:ok, source_module.extension_modules(source_opts)}
  rescue
    error ->
      {:error, Error.invalid(source_module, :extension_source_failed, callback_error: Diagnostics.exception(error))}
  catch
    kind, reason ->
      {:error, Error.invalid(source_module, :extension_source_failed, callback_error: Diagnostics.caught(kind, reason))}
  end

  defp sourced_modules(modules, source) do
    Enum.map(modules, &%{module: &1, source: source})
  end
end
