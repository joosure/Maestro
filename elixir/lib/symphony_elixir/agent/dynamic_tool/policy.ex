defmodule SymphonyElixir.Agent.DynamicTool.Policy do
  @moduledoc """
  Side-effect metadata and allowlist enforcement for dynamic tool execution.
  """

  alias SymphonyElixir.Agent.DynamicTool.{Context, Metadata}
  alias SymphonyElixir.Agent.DynamicTool.Policy.{Config, Contract, Decision}

  @default_side_effect Metadata.Contract.default_side_effect()
  @side_effect_key Metadata.Contract.side_effect()

  @type metadata :: %{
          required(String.t()) => String.t() | [String.t()] | boolean()
        }

  @spec metadata_many(term()) :: map()
  def metadata_many(tool_specs), do: tool_specs |> Metadata.from_tool_specs() |> Metadata.to_map_by_tool()

  @spec metadata_records_many(term()) :: %{String.t() => Metadata.t()}
  def metadata_records_many(tool_specs), do: Metadata.from_tool_specs(tool_specs)

  @spec metadata(term()) :: metadata()
  def metadata(tool_spec), do: tool_spec |> Metadata.normalize() |> Metadata.to_map()

  @spec metadata_record(term()) :: Metadata.t()
  def metadata_record(tool_spec), do: Metadata.normalize(tool_spec)

  @spec authorize(Context.t(), String.t(), Config.t()) :: :ok | {:error, Decision.t()}
  def authorize(%Context{} = tool_context, tool, %Config{} = config)
      when is_binary(tool) do
    side_effect = side_effect_for(tool_context, tool)

    cond do
      operator_only?(tool_context, tool) and not operator_tool_access?(tool_context, config) ->
        {:error, operator_only_decision(tool)}

      side_effect in config.allowed_side_effects ->
        :ok

      true ->
        {:error, side_effect_denied_decision(tool, side_effect, config.allowed_side_effects)}
    end
  end

  @spec side_effect_for(Context.t(), String.t()) :: String.t()
  def side_effect_for(%Context{} = tool_context, tool) when is_binary(tool) do
    tool_context
    |> Context.metadata_for(tool)
    |> then(& &1.side_effect)
  end

  def side_effect_for(_tool_context, _tool), do: @default_side_effect

  @spec operator_only?(Context.t(), String.t()) :: boolean()
  def operator_only?(%Context{} = tool_context, tool) when is_binary(tool) do
    tool_context
    |> Context.metadata_for(tool)
    |> then(&(&1.operator_only? == true))
  end

  def operator_only?(_tool_context, _tool), do: false

  @spec allowed_side_effects(Config.t()) :: [String.t()]
  def allowed_side_effects(%Config{allowed_side_effects: allowed_side_effects}), do: allowed_side_effects

  defp operator_tool_access?(%Context{} = tool_context, %Config{} = config) do
    config.allow_operator_tools? == true or config.exposure == :diagnostics or
      Context.tool_plan_exposure(tool_context) == "diagnostics"
  end

  defp operator_only_decision(tool) do
    Decision.reject(
      Contract.operator_only_denied(),
      Contract.operator_only_message(),
      %{
        Contract.tool_key() => tool,
        Contract.required_exposure_key() => "diagnostics"
      }
    )
  end

  defp side_effect_denied_decision(tool, side_effect, allowed_side_effects) do
    Decision.reject(
      Contract.side_effect_denied(),
      Contract.side_effect_denied_message(),
      %{
        Contract.tool_key() => tool,
        @side_effect_key => side_effect,
        Contract.allowed_side_effects_key() => allowed_side_effects
      }
    )
  end
end
