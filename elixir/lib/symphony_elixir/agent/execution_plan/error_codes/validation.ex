defmodule SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation do
  @moduledoc """
  Generic validation machine-code contract for Agent execution-plan records.

  These codes describe schema and request-shape validation. Evidence-specific
  append and immutability codes live under `ErrorCodes.Evidence`.
  """

  @schema_invalid "schema_invalid"
  @invalid_schema "invalid_schema"
  @invalid_type "invalid_type"
  @invalid_enum "invalid_enum"
  @unknown_key "unknown_key"
  @missing_required_field "missing_required_field"
  @invalid_extension_key "invalid_extension_key"

  @spec schema_invalid() :: String.t()
  def schema_invalid, do: @schema_invalid

  @spec invalid_schema() :: String.t()
  def invalid_schema, do: @invalid_schema

  @spec invalid_type() :: String.t()
  def invalid_type, do: @invalid_type

  @spec invalid_enum() :: String.t()
  def invalid_enum, do: @invalid_enum

  @spec unknown_key() :: String.t()
  def unknown_key, do: @unknown_key

  @spec missing_required_field() :: String.t()
  def missing_required_field, do: @missing_required_field

  @spec invalid_extension_key() :: String.t()
  def invalid_extension_key, do: @invalid_extension_key
end
