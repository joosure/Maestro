defmodule SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.FailureScope do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.ResourceIdentity

  @resource_kind_key "kind"
  @resource_id_key "id"

  defstruct run_id: nil,
            resource_kind: nil,
            resource_id: nil,
            tool: nil

  @type t :: %__MODULE__{
          run_id: String.t(),
          resource_kind: String.t(),
          resource_id: term(),
          tool: String.t()
        }

  @spec new(String.t() | nil, ResourceIdentity.t() | nil, String.t() | nil) :: {:ok, t()} | :unscoped
  def new(run_id, %ResourceIdentity{kind: resource_kind, id: resource_id}, tool) do
    with {:ok, run_id} <- normalize_text(run_id),
         {:ok, tool} <- normalize_text(tool),
         {:ok, resource_kind} <- normalize_text(resource_kind),
         true <- not is_nil(resource_id) do
      {:ok,
       %__MODULE__{
         run_id: run_id,
         resource_kind: resource_kind,
         resource_id: resource_id,
         tool: tool
       }}
    else
      _invalid -> :unscoped
    end
  end

  def new(_run_id, _identity, _tool), do: :unscoped

  @spec matches?(t(), t()) :: boolean()
  def matches?(%__MODULE__{} = left, %__MODULE__{} = right) do
    left.run_id == right.run_id and
      left.resource_kind == right.resource_kind and
      left.resource_id == right.resource_id and
      left.tool == right.tool
  end

  @spec resource_map(t()) :: map()
  def resource_map(%__MODULE__{resource_kind: kind, resource_id: id}) do
    %{@resource_kind_key => kind, @resource_id_key => id}
  end

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> :error
      trimmed -> {:ok, trimmed}
    end
  end

  defp normalize_text(_value), do: :error
end
