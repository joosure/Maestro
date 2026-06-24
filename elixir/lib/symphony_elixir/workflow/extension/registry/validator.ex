defmodule SymphonyElixir.Workflow.Extension.Registry.Validator do
  @moduledoc """
  Validation boundary for workflow runtime-extension registry assembly.

  The facade delegates option, source, duplicate-module, and duplicate-id checks
  here so the registry entrypoint stays a small orchestration layer.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.Registry.Entry
  alias SymphonyElixir.Workflow.Extension.Registry.Error
  alias SymphonyElixir.Workflow.Extension.Registry.Source

  @function_option_keys [:entries, :extra_entries, :sources, :extra_sources, :source_opts]

  @spec validate_opts(keyword()) :: :ok | {:error, map()}
  def validate_opts(opts) when is_list(opts) do
    unsupported_keys = if Keyword.keyword?(opts), do: Keyword.keys(opts) -- @function_option_keys, else: []

    cond do
      not Keyword.keyword?(opts) ->
        {:error, Error.invalid(:registry, :registry_opts_not_keyword, value_type: Diagnostics.type_atom(opts))}

      unsupported_keys != [] ->
        {:error, Error.invalid(:registry, :registry_opts_unknown_keys, keys: Enum.map(unsupported_keys, &inspect/1))}

      not Keyword.keyword?(Keyword.get(opts, :source_opts, [])) ->
        {:error, Error.invalid(:registry, :source_opts_not_keyword, value_type: Diagnostics.type_atom(Keyword.get(opts, :source_opts)))}

      true ->
        :ok
    end
  end

  def validate_opts(opts) do
    {:error, Error.invalid(:registry, :registry_opts_not_keyword, value_type: Diagnostics.type_atom(opts))}
  end

  @spec validate_source_module(term()) :: :ok | {:error, map()}
  def validate_source_module(source_module) do
    cond do
      not is_atom(source_module) or is_nil(source_module) ->
        {:error, Error.invalid(source_module, :invalid_extension_source_module)}

      not Code.ensure_loaded?(source_module) ->
        {:error, Error.invalid(source_module, :extension_source_not_loaded)}

      not function_exported?(source_module, :extension_modules, 1) ->
        {:error, Error.invalid(source_module, :extension_source_callback_missing)}

      not source_behaviour?(source_module) ->
        {:error, Error.invalid(source_module, :extension_source_behaviour_missing)}

      true ->
        :ok
    end
  end

  @spec validate_source_modules_list(module(), term()) :: :ok | {:error, map()}
  def validate_source_modules_list(_source_module, modules) when is_list(modules), do: :ok

  def validate_source_modules_list(source_module, modules) do
    {:error, Error.invalid(source_module, :extension_source_modules_not_list, value_type: Diagnostics.type_atom(modules))}
  end

  @spec validate_unique_modules([map()]) :: :ok | {:error, map()}
  def validate_unique_modules(specs) do
    duplicates =
      specs
      |> Enum.group_by(& &1.module)
      |> Enum.filter(fn {_module, specs} -> length(specs) > 1 end)
      |> Enum.map(fn {module, specs} ->
        %{
          module: inspect(module),
          sources: Enum.map(specs, &source_diagnostic(&1.source))
        }
      end)

    case duplicates do
      [] -> :ok
      duplicates -> {:error, Error.invalid(:registry, :duplicate_extension_modules, duplicates: duplicates)}
    end
  end

  @spec validate_unique_ids([Entry.t()]) :: :ok | {:error, map()}
  def validate_unique_ids(entries) do
    duplicates =
      entries
      |> Enum.group_by(& &1.id)
      |> Enum.filter(fn {_id, entries} -> length(entries) > 1 end)
      |> Enum.map(fn {id, entries} -> %{id: id, entries: Enum.map(entries, &Entry.diagnostic/1)} end)

    case duplicates do
      [] -> :ok
      duplicates -> {:error, Error.invalid(:registry, :duplicate_extension_ids, duplicates: duplicates)}
    end
  end

  defp source_behaviour?(source_module) do
    attributes = source_module.module_info(:attributes)

    behaviours =
      Keyword.get_values(attributes, :behaviour) ++
        Keyword.get_values(attributes, :behavior)

    Source in List.flatten(behaviours)
  end

  defp source_diagnostic({kind, source_module}) when kind in [:source, :extra_source] do
    %{kind: kind, source_module: inspect(source_module)}
  end

  defp source_diagnostic(source), do: source
end
