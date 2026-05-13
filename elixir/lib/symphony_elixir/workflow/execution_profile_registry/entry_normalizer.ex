defmodule SymphonyElixir.Workflow.ExecutionProfileRegistry.EntryNormalizer do
  @moduledoc false

  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Entry
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Values
  alias SymphonyElixir.Workflow.RoutePolicy

  @spec normalize_entries([term()]) :: {:ok, [Entry.t()]} | {:error, term()}
  def normalize_entries(raw_entries) do
    Enum.reduce_while(raw_entries, {:ok, []}, fn raw_entry, {:ok, entries} ->
      case normalize_entry(raw_entry) do
        {:ok, entry} -> {:cont, {:ok, [entry | entries]}}
        {:error, reason} -> {:halt, {:error, {:invalid_workflow_execution_profile_registry, reason}}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_entry(%Entry{} = entry), do: normalize_entry(Map.from_struct(entry))

  defp normalize_entry(raw_entry) when is_map(raw_entry) do
    normalize_entry_map(raw_entry)
  end

  defp normalize_entry(raw_entry) when is_list(raw_entry) do
    if Values.registry_entry_pair_list?(raw_entry) do
      raw_entry
      |> Map.new()
      |> normalize_entry_map()
    else
      {:error, {:invalid_registry_entry, raw_entry}}
    end
  end

  defp normalize_entry(raw_entry), do: {:error, {:invalid_registry_entry, raw_entry}}

  defp normalize_entry_map(raw_entry) do
    name = Values.normalize_name(Values.map_field(raw_entry, :name))
    profile_kind = Values.normalize_non_empty_string(Values.map_field(raw_entry, :profile_kind))
    profile_versions = normalize_profile_versions(raw_entry)
    supported_actions = normalize_supported_actions(Values.map_field(raw_entry, :supported_actions))
    required_capabilities = normalize_capabilities(Values.map_field(raw_entry, :required_capabilities))
    runtime_handler = normalize_runtime_handler(Values.map_field(raw_entry, :runtime_handler))

    cond do
      is_nil(name) ->
        {:error, {:invalid_registry_entry_name, raw_entry}}

      is_nil(profile_kind) ->
        {:error, {:invalid_registry_entry_profile_kind, raw_entry}}

      profile_versions == [] ->
        {:error, {:invalid_registry_entry_profile_versions, raw_entry}}

      supported_actions == [] ->
        {:error, {:invalid_registry_entry_supported_actions, raw_entry}}

      is_nil(required_capabilities) ->
        {:error, {:invalid_registry_entry_required_capabilities, raw_entry}}

      is_nil(runtime_handler) ->
        {:error, {:invalid_registry_entry_runtime_handler, raw_entry}}

      true ->
        with {:ok, handler_capabilities} <- validate_runtime_handler(runtime_handler, supported_actions) do
          {:ok,
           %Entry{
             name: name,
             profile_kind: profile_kind,
             profile_versions: profile_versions,
             supported_actions: supported_actions,
             required_capabilities: Enum.uniq(handler_capabilities ++ required_capabilities),
             runtime_handler: runtime_handler
           }}
        end
    end
  end

  defp normalize_runtime_handler(module) when is_atom(module) and not is_nil(module), do: module

  defp normalize_runtime_handler(module_name) when is_binary(module_name) do
    module_name
    |> normalize_module_name()
    |> existing_atom()
  end

  defp normalize_runtime_handler(_runtime_handler), do: nil

  defp validate_runtime_handler(runtime_handler, supported_actions) when is_atom(runtime_handler) do
    with :ok <- ensure_runtime_handler_loaded(runtime_handler),
         :ok <- ensure_runtime_handler_callback(runtime_handler, :supported_actions, 0),
         :ok <- ensure_runtime_handler_callback(runtime_handler, :required_capabilities, 0),
         :ok <- ensure_runtime_handler_callback(runtime_handler, :run, 1),
         {:ok, handler_supported_actions} <- runtime_handler_supported_actions(runtime_handler),
         :ok <- validate_runtime_handler_action_scope(runtime_handler, supported_actions, handler_supported_actions),
         {:ok, handler_capabilities} <- runtime_handler_required_capabilities(runtime_handler) do
      {:ok, handler_capabilities}
    end
  end

  defp ensure_runtime_handler_loaded(runtime_handler) do
    if Code.ensure_loaded?(runtime_handler) do
      :ok
    else
      {:error, {:invalid_registry_entry_runtime_handler_module, runtime_handler}}
    end
  end

  defp ensure_runtime_handler_callback(runtime_handler, callback, arity) do
    if function_exported?(runtime_handler, callback, arity) do
      :ok
    else
      {:error, {:invalid_registry_entry_runtime_handler_contract, runtime_handler, {callback, arity}}}
    end
  end

  defp runtime_handler_supported_actions(runtime_handler) do
    runtime_handler
    |> then(& &1.supported_actions())
    |> normalize_supported_actions()
    |> case do
      [] -> {:error, {:invalid_registry_entry_runtime_handler_supported_actions, runtime_handler}}
      supported_actions -> {:ok, supported_actions}
    end
  end

  defp validate_runtime_handler_action_scope(runtime_handler, entry_actions, handler_actions) do
    unsupported_actions = entry_actions -- handler_actions

    case unsupported_actions do
      [] -> :ok
      _ -> {:error, {:unsupported_registry_entry_runtime_handler_actions, runtime_handler, unsupported_actions}}
    end
  end

  defp runtime_handler_required_capabilities(runtime_handler) do
    runtime_handler
    |> then(& &1.required_capabilities())
    |> normalize_capabilities()
    |> case do
      nil -> {:error, {:invalid_registry_entry_runtime_handler_required_capabilities, runtime_handler}}
      capabilities -> {:ok, capabilities}
    end
  end

  defp normalize_profile_versions(raw_entry) do
    raw_entry
    |> Values.map_field(:profile_versions)
    |> List.wrap()
    |> Enum.map(&Values.normalize_positive_integer/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_supported_actions(values) do
    values
    |> List.wrap()
    |> Enum.map(&RoutePolicy.normalize_action/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_capabilities(nil), do: []

  defp normalize_capabilities(values) when is_list(values) do
    normalized =
      values
      |> Enum.map(&Values.normalize_non_empty_string/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if length(normalized) == length(values), do: normalized
  end

  defp normalize_capabilities(_values), do: nil

  defp normalize_module_name(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      "Elixir." <> _rest = module_name -> module_name
      module_name -> "Elixir." <> module_name
    end
  end

  defp existing_atom(nil), do: nil

  defp existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end
end
