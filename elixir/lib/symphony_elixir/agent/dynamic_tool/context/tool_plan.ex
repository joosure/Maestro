defmodule SymphonyElixir.Agent.DynamicTool.Context.ToolPlan do
  @moduledoc false

  @exposure_key "exposure"
  @required_capabilities_key "required_capabilities"
  @tool_names_key "tool_names"
  @resolved_tools_key "resolved_tools"
  @reason_key "reason"

  defstruct exposure: nil,
            required_capabilities: [],
            tool_names: [],
            resolved_tools: [],
            reason: nil

  @type t :: %__MODULE__{
          exposure: String.t() | nil,
          required_capabilities: [String.t()],
          tool_names: [String.t()],
          resolved_tools: [term()],
          reason: String.t() | nil
        }

  @spec new(keyword() | map()) :: {:ok, t()} | :error
  def new(attrs) when is_list(attrs) do
    attrs
    |> Map.new()
    |> new_from_internal_map()
  end

  def new(%__MODULE__{} = plan), do: normalize_struct(plan)

  def new(attrs) when is_map(attrs), do: new_from_internal_map(attrs)
  def new(_attrs), do: :error

  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, plan} -> plan
      :error -> raise ArgumentError, "invalid dynamic tool context tool plan: #{inspect(attrs)}"
    end
  end

  @spec normalize(term()) :: {:ok, t() | nil} | :error
  def normalize(%__MODULE__{} = plan), do: normalize_struct(plan)

  def normalize(plan) when is_map(plan) do
    if canonical_string_key_map?(plan), do: new_from_canonical_map(plan), else: :error
  end

  def normalize(nil), do: {:ok, nil}
  def normalize(_plan), do: :error

  @spec exposure(t() | nil) :: String.t() | nil
  def exposure(%__MODULE__{exposure: exposure}), do: exposure
  def exposure(nil), do: nil

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = plan) do
    %{
      @exposure_key => plan.exposure,
      @required_capabilities_key => plan.required_capabilities,
      @tool_names_key => plan.tool_names,
      @resolved_tools_key => plan.resolved_tools,
      @reason_key => plan.reason
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp new_from_internal_map(attrs) when is_map(attrs) do
    with {:ok, exposure} <- optional_string(Map.get(attrs, :exposure)),
         {:ok, required_capabilities} <- string_list(Map.get(attrs, :required_capabilities, [])),
         {:ok, tool_names} <- string_list(Map.get(attrs, :tool_names, [])),
         {:ok, resolved_tools} <- term_list(Map.get(attrs, :resolved_tools, [])),
         {:ok, reason} <- optional_string(Map.get(attrs, :reason)) do
      {:ok,
       %__MODULE__{
         exposure: exposure,
         required_capabilities: required_capabilities,
         tool_names: tool_names,
         resolved_tools: resolved_tools,
         reason: reason
       }}
    end
  end

  defp new_from_canonical_map(attrs) when is_map(attrs) do
    with {:ok, exposure} <- optional_string(Map.get(attrs, @exposure_key)),
         {:ok, required_capabilities} <- string_list(Map.get(attrs, @required_capabilities_key, [])),
         {:ok, tool_names} <- string_list(Map.get(attrs, @tool_names_key, [])),
         {:ok, resolved_tools} <- term_list(Map.get(attrs, @resolved_tools_key, [])),
         {:ok, reason} <- optional_string(Map.get(attrs, @reason_key)) do
      {:ok,
       %__MODULE__{
         exposure: exposure,
         required_capabilities: required_capabilities,
         tool_names: tool_names,
         resolved_tools: resolved_tools,
         reason: reason
       }}
    end
  end

  defp normalize_struct(%__MODULE__{} = plan) do
    new_from_internal_map(%{
      exposure: plan.exposure,
      required_capabilities: plan.required_capabilities,
      tool_names: plan.tool_names,
      resolved_tools: plan.resolved_tools,
      reason: plan.reason
    })
  end

  defp canonical_string_key_map?(map) when is_map(map), do: Enum.all?(Map.keys(map), &is_binary/1)

  defp optional_string(nil), do: {:ok, nil}

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, nil}
      normalized -> {:ok, normalized}
    end
  end

  defp optional_string(_value), do: :error

  defp string_list(values) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn
      value, {:ok, acc} when is_binary(value) ->
        case optional_string(value) do
          {:ok, nil} -> {:cont, {:ok, acc}}
          {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
          :error -> {:halt, :error}
        end

      _value, _acc ->
        {:halt, :error}
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      :error -> :error
    end
  end

  defp string_list(_values), do: :error

  defp term_list(values) when is_list(values), do: {:ok, values}
  defp term_list(_values), do: :error
end
