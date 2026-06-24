defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.RequestBuilder.RawInput do
  @moduledoc """
  Raw input helpers for `AdoptionInitializer.RequestBuilder`.

  This module is intentionally scoped under `RequestBuilder` so raw atom/string
  key handling remains outside the internal adoption initializer model.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields

  @structured_execution_plan_key "structured_execution_plan"
  @enabled_key "enabled"

  @workflow_key "workflow"
  @profile_key "profile"
  @options_key "options"
  @tracker_key "tracker"
  @kind_key "kind"
  @version_key "version"
  @id_key "id"
  @identifier_key "identifier"

  @plan_id_key Fields.plan_id()
  @run_id_key Fields.run_id()
  @issue_id_key Fields.issue_id()
  @issue_identifier_key Fields.issue_identifier()
  @tracker_kind_key Fields.tracker_kind()
  @route_key_key Fields.route_key()
  @status_key Fields.status()
  @created_at_key Fields.created_at()
  @updated_at_key Fields.updated_at()

  @key_atoms %{
    @workflow_key => :workflow,
    @profile_key => :profile,
    @options_key => :options,
    @structured_execution_plan_key => :structured_execution_plan,
    @tracker_key => :tracker,
    @enabled_key => :enabled,
    @kind_key => :kind,
    @version_key => :version,
    @id_key => :id,
    @identifier_key => :identifier,
    @plan_id_key => :plan_id,
    @run_id_key => :run_id,
    @issue_id_key => :issue_id,
    @issue_identifier_key => :issue_identifier,
    @tracker_kind_key => :tracker_kind,
    @route_key_key => :route_key,
    @status_key => :status,
    @created_at_key => :created_at,
    @updated_at_key => :updated_at
  }

  @spec structured_execution_plan_key() :: String.t()
  def structured_execution_plan_key, do: @structured_execution_plan_key

  @spec enabled_key() :: String.t()
  def enabled_key, do: @enabled_key

  @spec workflow_key() :: String.t()
  def workflow_key, do: @workflow_key

  @spec profile_key() :: String.t()
  def profile_key, do: @profile_key

  @spec options_key() :: String.t()
  def options_key, do: @options_key

  @spec tracker_key() :: String.t()
  def tracker_key, do: @tracker_key

  @spec kind_key() :: String.t()
  def kind_key, do: @kind_key

  @spec id_key() :: String.t()
  def id_key, do: @id_key

  @spec identifier_key() :: String.t()
  def identifier_key, do: @identifier_key

  @spec map_value(term(), String.t() | atom()) :: term()
  def map_value(map, key)

  def map_value(%{} = map, key) when is_binary(key) do
    key
    |> atom_for_key()
    |> case do
      atom_key when is_atom(atom_key) -> normalize_value(Map.get(map, key) || Map.get(map, atom_key))
      nil -> normalize_value(Map.get(map, key))
    end
  end

  def map_value(%{} = map, key) when is_atom(key), do: normalize_value(Map.get(map, key) || Map.get(map, Atom.to_string(key)))
  def map_value(_map, _key), do: nil

  @spec keyword_value(keyword(), String.t()) :: term()
  def keyword_value(opts, key) when is_list(opts) and is_binary(key) do
    case atom_for_key(key) do
      atom_key when is_atom(atom_key) -> Keyword.get(opts, atom_key)
      nil -> nil
    end
  end

  @spec normalize_map(term()) :: map()
  def normalize_map(%{} = map), do: map
  def normalize_map(_value), do: %{}

  @spec put_key(map(), String.t(), term()) :: map()
  def put_key(map, key, value) when is_map(map) and is_binary(key) do
    atom_key = atom_for_key(key)

    cond do
      Map.has_key?(map, key) -> Map.put(map, key, value)
      is_atom(atom_key) and Map.has_key?(map, atom_key) -> Map.put(map, atom_key, value)
      true -> Map.put(map, key, value)
    end
  end

  @spec delete_key(map(), String.t()) :: map()
  def delete_key(map, key) when is_map(map) and is_binary(key) do
    atom_key = atom_for_key(key)

    map
    |> Map.delete(key)
    |> then(fn map -> if is_atom(atom_key), do: Map.delete(map, atom_key), else: map end)
  end

  @spec present?(term()) :: boolean()
  def present?(value) when is_binary(value), do: String.trim(value) != ""
  def present?(_value), do: false

  defp atom_for_key(key) when is_binary(key), do: Map.get(@key_atoms, key)

  defp normalize_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_value(value), do: value
end
