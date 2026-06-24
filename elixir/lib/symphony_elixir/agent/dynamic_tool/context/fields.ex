defmodule SymphonyElixir.Agent.DynamicTool.Context.Fields do
  @moduledoc false

  @source :source
  @source_context :source_context
  @source_kind :source_kind
  @tool_specs :tool_specs
  @tool_metadata :tool_metadata
  @tool_environment :tool_environment
  @runtime_metadata :runtime_metadata
  @adoption_settings :adoption_settings
  @tool_plan :tool_plan

  @spec source() :: atom()
  def source, do: @source

  @spec source_context() :: atom()
  def source_context, do: @source_context

  @spec source_kind() :: atom()
  def source_kind, do: @source_kind

  @spec tool_specs() :: atom()
  def tool_specs, do: @tool_specs

  @spec tool_metadata() :: atom()
  def tool_metadata, do: @tool_metadata

  @spec tool_environment() :: atom()
  def tool_environment, do: @tool_environment

  @spec runtime_metadata() :: atom()
  def runtime_metadata, do: @runtime_metadata

  @spec adoption_settings() :: atom()
  def adoption_settings, do: @adoption_settings

  @spec tool_plan() :: atom()
  def tool_plan, do: @tool_plan

  @spec key(atom()) :: String.t()
  def key(field) when is_atom(field), do: Atom.to_string(field)

  @spec value(map(), atom()) :: term()
  def value(%_{} = struct, field) when is_atom(field), do: Map.get(struct, field)
  def value(map, field) when is_map(map) and is_atom(field), do: Map.get(map, key(field))

  def value(_map, _field), do: nil

  @spec fetch(map(), atom()) :: {:ok, term()} | :error
  def fetch(%_{} = struct, field) when is_atom(field) do
    if Map.has_key?(struct, field), do: {:ok, Map.get(struct, field)}, else: :error
  end

  def fetch(map, field) when is_map(map) and is_atom(field) do
    string_key = key(field)

    if Map.has_key?(map, string_key), do: {:ok, Map.get(map, string_key)}, else: :error
  end

  def fetch(_map, _field), do: :error
end
