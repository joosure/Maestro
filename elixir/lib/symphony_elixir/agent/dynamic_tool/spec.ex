defmodule SymphonyElixir.Agent.DynamicTool.Spec do
  @moduledoc """
  Normalizes provider-neutral dynamic tool specs before provider registration.
  """

  alias SymphonyElixir.Agent.DynamicTool.ToolSpec

  @type json_value :: ToolSpec.json_value()
  @type t :: %{
          required(String.t()) => json_value()
        }

  @spec normalize(term()) :: {:ok, t()} | :error
  def normalize(tool_spec) do
    case ToolSpec.normalize(tool_spec) do
      {:ok, record} -> {:ok, ToolSpec.to_map(record)}
      :error -> :error
    end
  end

  @spec normalize_record(term()) :: {:ok, ToolSpec.t()} | :error
  defdelegate normalize_record(tool_spec), to: ToolSpec, as: :normalize

  @spec normalize_records_strict(term()) :: {:ok, [ToolSpec.t()]} | {:error, [ToolSpec.Error.t()]}
  defdelegate normalize_records_strict(tool_specs), to: ToolSpec, as: :normalize_many_strict

  @spec normalize_many_strict(term()) :: {:ok, [t()]} | {:error, [ToolSpec.Error.t()]}
  def normalize_many_strict(tool_specs) do
    case ToolSpec.normalize_many_strict(tool_specs) do
      {:ok, records} -> {:ok, ToolSpec.to_maps(records)}
      {:error, errors} -> {:error, errors}
    end
  end

  @spec valid_name?(term()) :: boolean()
  defdelegate valid_name?(name), to: ToolSpec

  @spec name_key() :: String.t()
  defdelegate name_key, to: ToolSpec

  @spec description_key() :: String.t()
  defdelegate description_key, to: ToolSpec

  @spec input_schema_key() :: String.t()
  defdelegate input_schema_key, to: ToolSpec
end
