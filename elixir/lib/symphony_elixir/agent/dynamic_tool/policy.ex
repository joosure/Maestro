defmodule SymphonyElixir.Agent.DynamicTool.Policy do
  @moduledoc """
  Side-effect metadata and allowlist enforcement for dynamic tool execution.
  """

  alias SymphonyElixir.Agent.DynamicTool.Spec

  @side_effect_classes ~w(read_only write destructive)
  @default_side_effect "destructive"
  @default_allowed_side_effects @side_effect_classes

  @type metadata :: %{
          required(String.t()) => String.t() | [String.t()] | boolean()
        }

  @spec metadata_many(term()) :: map()
  def metadata_many(tool_specs) when is_list(tool_specs) do
    {_seen, metadata} =
      Enum.reduce(tool_specs, {MapSet.new(), %{}}, fn tool_spec, {seen, metadata} ->
        case Spec.normalize(tool_spec) do
          {:ok, %{"name" => name}} ->
            if MapSet.member?(seen, name) do
              {seen, metadata}
            else
              {MapSet.put(seen, name), Map.put(metadata, name, metadata(tool_spec))}
            end

          :error ->
            {seen, metadata}
        end
      end)

    metadata
  end

  def metadata_many(_tool_specs), do: %{}

  @spec metadata(term()) :: metadata()
  def metadata(tool_spec) when is_map(tool_spec) do
    %{}
    |> Map.put("sideEffect", side_effect(tool_spec))
    |> Map.put("schemaVersion", string_field(tool_spec, ["schemaVersion", "schema_version"], "1"))
    |> Map.put("riskFlags", risk_flags(tool_spec))
    |> maybe_put_string(
      "workflowCapability",
      string_field(tool_spec, ["workflowCapability", "workflow_capability"], nil)
    )
    |> maybe_put_string("sourceKind", string_field(tool_spec, ["sourceKind", "source_kind"], nil))
    |> maybe_put_boolean("deprecated", boolean_field(tool_spec, ["deprecated"], false))
    |> maybe_put_boolean(
      "operatorOnly",
      boolean_field(tool_spec, ["operatorOnly", "operator_only"], false)
    )
  end

  def metadata(_tool_spec) do
    %{
      "sideEffect" => @default_side_effect,
      "schemaVersion" => "1",
      "riskFlags" => []
    }
  end

  @spec authorize(map(), String.t(), keyword()) :: :ok | {:error, map()}
  def authorize(tool_context, tool, opts \\ [])
      when is_map(tool_context) and is_binary(tool) and is_list(opts) do
    side_effect = side_effect_for(tool_context, tool)
    allowed_side_effects = allowed_side_effects(opts)

    cond do
      operator_only?(tool_context, tool) and not operator_tool_access?(tool_context, opts) ->
        {:error,
         %{
           "error" => %{
             "code" => "operator_only_dynamic_tool_denied",
             "message" => "Operator-only dynamic tool requires explicit diagnostics exposure.",
             "tool" => tool,
             "requiredExposure" => "diagnostics"
           }
         }}

      side_effect in allowed_side_effects ->
        :ok

      true ->
        {:error,
         %{
           "error" => %{
             "message" => "Dynamic tool side-effect class is not allowed by policy.",
             "tool" => tool,
             "sideEffect" => side_effect,
             "allowedSideEffects" => allowed_side_effects
           }
         }}
    end
  end

  @spec side_effect_for(map(), String.t()) :: String.t()
  def side_effect_for(%{tool_metadata: tool_metadata}, tool)
      when is_map(tool_metadata) and is_binary(tool) do
    tool_metadata
    |> Map.get(tool, %{})
    |> side_effect()
  end

  def side_effect_for(_tool_context, _tool), do: @default_side_effect

  @spec operator_only?(map(), String.t()) :: boolean()
  def operator_only?(%{tool_metadata: tool_metadata}, tool)
      when is_map(tool_metadata) and is_binary(tool) do
    tool_metadata
    |> Map.get(tool, %{})
    |> Map.get("operatorOnly", false)
    |> Kernel.==(true)
  end

  def operator_only?(_tool_context, _tool), do: false

  @spec allowed_side_effects(keyword()) :: [String.t()]
  def allowed_side_effects(opts \\ []) when is_list(opts) do
    opts
    |> Keyword.get(:dynamic_tool_policy, configured_policy())
    |> normalize_allowed_side_effects()
  end

  defp configured_policy do
    Application.get_env(:symphony_elixir, :dynamic_tool_policy, %{
      allowed_side_effects: @default_allowed_side_effects
    })
  end

  defp normalize_allowed_side_effects(%{} = policy) do
    policy
    |> policy_field(
      [:allowed_side_effects, "allowed_side_effects", :allowedSideEffects, "allowedSideEffects"],
      @default_allowed_side_effects
    )
    |> normalize_side_effect_list()
  end

  defp normalize_allowed_side_effects(policy) when is_list(policy),
    do: normalize_side_effect_list(policy)

  defp normalize_allowed_side_effects(_policy), do: @default_allowed_side_effects

  defp operator_tool_access?(tool_context, opts) when is_map(tool_context) and is_list(opts) do
    exposure =
      opts
      |> Keyword.get(:dynamic_tool_exposure)
      |> normalize_exposure()

    exposure == :diagnostics or context_exposure(tool_context) == "diagnostics" or
      opts
      |> Keyword.get(:dynamic_tool_policy, %{})
      |> policy_field(
        [
          :allow_operator_tools,
          "allow_operator_tools",
          :allowOperatorTools,
          "allowOperatorTools"
        ],
        false
      )
      |> Kernel.==(true)
  end

  defp context_exposure(%{tool_plan: %{exposure: exposure}}) when is_binary(exposure),
    do: exposure

  defp context_exposure(%{"tool_plan" => %{"exposure" => exposure}}) when is_binary(exposure),
    do: exposure

  defp context_exposure(_tool_context), do: nil

  defp normalize_side_effect_list(values) when is_list(values) do
    values
    |> Enum.map(&normalize_side_effect_value/1)
    |> Enum.filter(&(&1 in @side_effect_classes))
    |> Enum.uniq()
  end

  defp normalize_side_effect_list(_values), do: @default_allowed_side_effects

  defp policy_field(map, fields, default) when is_map(map) and is_list(fields) do
    Enum.find_value(fields, default, fn field -> Map.get(map, field) end)
  end

  defp policy_field(_value, _fields, default), do: default

  defp side_effect(tool_spec) when is_map(tool_spec) do
    tool_spec
    |> string_field(
      ["sideEffect", "side_effect", "sideEffectClass", "side_effect_class"],
      @default_side_effect
    )
    |> normalize_side_effect_value()
    |> case do
      side_effect when side_effect in @side_effect_classes -> side_effect
      _side_effect -> @default_side_effect
    end
  end

  defp side_effect(_tool_spec), do: @default_side_effect

  defp risk_flags(tool_spec) do
    case field_value(tool_spec, ["riskFlags", "risk_flags"]) do
      flags when is_list(flags) ->
        flags
        |> Enum.map(&normalize_string/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      _flags ->
        []
    end
  end

  defp string_field(map, fields, default) do
    map
    |> field_value(fields)
    |> normalize_string()
    |> case do
      nil -> default
      value -> value
    end
  end

  defp field_value(map, fields) when is_map(map) and is_list(fields) do
    Enum.find_value(fields, fn field ->
      Map.get(map, field) || Map.get(map, atom_field(field))
    end)
  end

  defp field_value(_map, _fields), do: nil

  defp boolean_field(map, fields, default) do
    case field_value(map, fields) do
      value when is_boolean(value) -> value
      _value -> default
    end
  end

  defp maybe_put_string(map, _key, nil), do: map
  defp maybe_put_string(map, key, value) when is_binary(value), do: Map.put(map, key, value)

  defp maybe_put_boolean(map, _key, false), do: map
  defp maybe_put_boolean(map, key, true), do: Map.put(map, key, true)

  defp normalize_side_effect_value(value) do
    value
    |> normalize_string()
    |> case do
      "readonly" -> "read_only"
      side_effect -> side_effect
    end
  end

  defp normalize_exposure(:diagnostics), do: :diagnostics
  defp normalize_exposure("diagnostics"), do: :diagnostics
  defp normalize_exposure(_exposure), do: nil

  defp normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_string()

  defp normalize_string(_value), do: nil

  defp atom_field("sideEffect"), do: :sideEffect
  defp atom_field("side_effect"), do: :side_effect
  defp atom_field("sideEffectClass"), do: :sideEffectClass
  defp atom_field("side_effect_class"), do: :side_effect_class
  defp atom_field("schemaVersion"), do: :schemaVersion
  defp atom_field("schema_version"), do: :schema_version
  defp atom_field("riskFlags"), do: :riskFlags
  defp atom_field("risk_flags"), do: :risk_flags
  defp atom_field("workflowCapability"), do: :workflowCapability
  defp atom_field("workflow_capability"), do: :workflow_capability
  defp atom_field("sourceKind"), do: :sourceKind
  defp atom_field("source_kind"), do: :source_kind
  defp atom_field("deprecated"), do: :deprecated
  defp atom_field("operatorOnly"), do: :operatorOnly
  defp atom_field("operator_only"), do: :operator_only
  defp atom_field(_field), do: nil
end
