defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.RawInput do
  @moduledoc """
  Raw provider-session event payload boundary.

  This module is the only provider-session event layer that accepts atom-keyed
  input maps and provider-specific aliases. Normalized canonical events should
  be consumed through `ProviderSessionEvent.Contract`.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Contract

  @provider_alias_key "provider"
  @id_alias_key "id"
  @hook_key "hook"
  @payload_key "payload"

  @task_collection_keys ~w(tasks todos plan entries items)
  @task_id_keys ~w(provider_task_id task_id id uuid)
  @task_title_keys ~w(title content text description name summary)
  @task_note_keys ~w(note notes details)
  @task_status_keys ~w(status state phase)
  @hook_name_keys ~w(hook_name name)

  @spec provider_kind(map(), keyword()) :: String.t() | nil
  def provider_kind(event, opts) when is_map(event) and is_list(opts) do
    string_value(event, Contract.provider_kind_key()) || string_value(event, @provider_alias_key) || keyword_string(opts, :provider_kind)
  end

  @spec run_id(map(), keyword()) :: String.t() | nil
  def run_id(event, opts) when is_map(event) and is_list(opts) do
    string_value(event, Contract.run_id_key()) || keyword_string(opts, :run_id)
  end

  @spec observed_at(map(), keyword()) :: String.t() | nil
  def observed_at(event, opts) when is_map(event) and is_list(opts) do
    string_value(event, Contract.observed_at_key()) || keyword_string(opts, :observed_at)
  end

  @spec surface(map()) :: String.t() | nil
  def surface(event) when is_map(event), do: string_value(event, Contract.surface_key())

  @spec event_id(map()) :: String.t() | nil
  def event_id(event) when is_map(event), do: string_value(event, Contract.event_id_key()) || string_value(event, @id_alias_key)

  @spec trust_class(map()) :: String.t() | nil
  def trust_class(event) when is_map(event), do: string_value(event, Contract.trust_class_key())

  @spec task_values(map()) :: [term()]
  def task_values(event) when is_map(event) do
    Enum.find_value(@task_collection_keys, [], fn key ->
      case fetch_existing(event, key) do
        values when is_list(values) -> values
        _value -> nil
      end
    end)
  end

  @spec hook_source(map()) :: map() | nil
  def hook_source(event) when is_map(event) do
    case fetch_existing(event, @hook_key) do
      hook when is_map(hook) -> hook
      _value -> nil
    end
  end

  @spec hook_present?(map()) :: boolean()
  def hook_present?(event) when is_map(event), do: not is_nil(fetch_existing(event, @hook_key))

  @spec payload(map()) :: term()
  def payload(event) when is_map(event), do: fetch_existing(event, @payload_key) || event

  @spec task_id(map()) :: String.t() | nil
  def task_id(task) when is_map(task) do
    @task_id_keys
    |> Enum.find_value(&string_value(task, &1))
    |> Kernel.||(nil)
  end

  @spec task_title(map()) :: String.t() | nil
  def task_title(task) when is_map(task), do: Enum.find_value(@task_title_keys, &string_value(task, &1))

  @spec task_note(map()) :: String.t() | nil
  def task_note(task) when is_map(task), do: Enum.find_value(@task_note_keys, &string_value(task, &1))

  @spec task_status(map()) :: String.t() | nil
  def task_status(task) when is_map(task), do: Enum.find_value(@task_status_keys, &string_value(task, &1))

  @spec hook_name(map()) :: String.t() | nil
  def hook_name(hook) when is_map(hook), do: Enum.find_value(@hook_name_keys, &string_value(hook, &1))

  @spec hook_phase(map()) :: String.t() | nil
  def hook_phase(hook) when is_map(hook), do: string_value(hook, Contract.phase_key())

  @spec hook_status(map()) :: String.t() | nil
  def hook_status(hook) when is_map(hook), do: string_value(hook, Contract.status_key())

  @spec string_value(term(), String.t()) :: String.t() | nil
  def string_value(map, key) when is_map(map) and is_binary(key) do
    case fetch_existing(map, key) do
      value when is_binary(value) -> value
      value when is_integer(value) -> Integer.to_string(value)
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      _value -> nil
    end
  end

  def string_value(_map, _key), do: nil

  @spec keyword_string(keyword(), atom()) :: String.t() | nil
  def keyword_string(opts, key) when is_list(opts) and is_atom(key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) -> value
      value when is_integer(value) -> Integer.to_string(value)
      _value -> nil
    end
  end

  defp fetch_existing(map, key) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> map_get_existing_atom(map, key)
    end
  end

  defp fetch_existing(_map, _key), do: nil

  defp map_get_existing_atom(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end
end
