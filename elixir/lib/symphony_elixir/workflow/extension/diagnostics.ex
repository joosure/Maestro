defmodule SymphonyElixir.Workflow.Extension.Diagnostics do
  @moduledoc """
  Shared bounded diagnostics for the workflow extension platform boundary.

  This module owns only generic value-type and exception-kind labels used by
  extension registries, dispatchers, and runtime envelopes. It intentionally
  does not encode registry source details, command vocabularies, schema
  identifiers, domain-owned fields, or raw values.
  """

  @type type_atom :: :atom | :string | :function | :list | :map | :term
  @type detailed_type_atom ::
          :atom
          | :float
          | :function
          | :integer
          | :list
          | :map
          | :pid
          | :reference
          | :string
          | :struct
          | :term
          | :tuple
          | nil

  @spec type_name(term()) :: String.t()
  def type_name(value) when is_boolean(value), do: "boolean"
  def type_name(value) when is_atom(value) and not is_nil(value), do: "atom"
  def type_name(value) when is_binary(value), do: "string"
  def type_name(value) when is_integer(value), do: "integer"
  def type_name(value) when is_float(value), do: "float"
  def type_name(value) when is_list(value), do: "list"
  def type_name(value) when is_map(value), do: "map"
  def type_name(nil), do: "nil"
  def type_name(_value), do: "term"

  @spec type_atom(term()) :: type_atom()
  def type_atom(value) when is_list(value), do: :list
  def type_atom(value) when is_map(value), do: :map
  def type_atom(value) when is_function(value), do: :function
  def type_atom(value) when is_binary(value), do: :string
  def type_atom(value) when is_atom(value), do: :atom
  def type_atom(_value), do: :term

  @spec detailed_type_atom(term()) :: detailed_type_atom()
  def detailed_type_atom(value) when is_struct(value), do: :struct
  def detailed_type_atom(value) when is_map(value), do: :map
  def detailed_type_atom(value) when is_tuple(value), do: :tuple
  def detailed_type_atom(nil), do: nil
  def detailed_type_atom(value) when is_atom(value), do: :atom
  def detailed_type_atom(value) when is_function(value), do: :function
  def detailed_type_atom(value) when is_pid(value), do: :pid
  def detailed_type_atom(value) when is_reference(value), do: :reference
  def detailed_type_atom(value) when is_list(value), do: :list
  def detailed_type_atom(value) when is_binary(value), do: :string
  def detailed_type_atom(value) when is_integer(value), do: :integer
  def detailed_type_atom(value) when is_float(value), do: :float
  def detailed_type_atom(_value), do: :term

  @spec exception(Exception.t()) :: %{required(:kind) => :error, required(:exception) => String.t()}
  def exception(error), do: %{kind: :error, exception: inspect(error.__struct__)}

  @spec caught(term(), term()) :: %{required(:kind) => term(), required(:reason_type) => String.t()}
  def caught(kind, reason), do: %{kind: kind, reason_type: type_name(reason)}
end
