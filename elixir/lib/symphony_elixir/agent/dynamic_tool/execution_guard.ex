defmodule SymphonyElixir.Agent.DynamicTool.ExecutionGuard do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.{Context, EventContract, Metadata}
  alias SymphonyElixir.Agent.DynamicTool.ExecutionGuard.{Contract, Decision}

  @side_effect_key Metadata.Contract.side_effect()
  @side_effect_classes Metadata.Contract.side_effect_classes()

  @spec ensure_authoritative_typed_tool(Context.t(), String.t() | nil) :: :ok | {:error, Decision.t()}
  def ensure_authoritative_typed_tool(%Context{} = tool_context, tool) when is_binary(tool) do
    metadata = Context.metadata_for(tool_context, tool)

    cond do
      not typed?(metadata) ->
        {:error, untyped_tool_decision(tool)}

      provider_alias?(metadata) ->
        {:error, alias_tool_decision(tool, metadata.tool_alias_of)}

      not Metadata.valid_side_effect?(metadata) ->
        {:error, invalid_side_effect_decision(tool, Metadata.side_effect_error(metadata))}

      true ->
        :ok
    end
  end

  def ensure_authoritative_typed_tool(%Context{}, tool) do
    {:error, untyped_tool_decision(inspect(tool))}
  end

  @spec typed?(Metadata.t()) :: boolean()
  def typed?(%Metadata{capability: capability}), do: non_empty_string?(capability)
  def typed?(_metadata), do: false

  @spec provider_alias?(Metadata.t()) :: boolean()
  def provider_alias?(%Metadata{tool_alias_of: alias_of}), do: non_empty_string?(alias_of)
  def provider_alias?(_metadata), do: false

  defp untyped_tool_decision(tool) do
    Decision.reject(
      EventContract.untyped_tool(),
      Contract.untyped_tool_message(),
      %{Contract.tool_key() => tool}
    )
  end

  defp alias_tool_decision(tool, alias_of) do
    Decision.reject(
      EventContract.alias_tool(),
      Contract.alias_tool_message(),
      %{
        Contract.tool_key() => tool,
        Contract.tool_alias_of_key() => alias_of
      }
    )
  end

  defp invalid_side_effect_decision(tool, :missing) do
    Decision.reject(
      EventContract.invalid_tool_metadata(),
      Contract.invalid_side_effect_message(),
      %{
        Contract.tool_key() => tool,
        Contract.field_key() => @side_effect_key,
        Contract.reason_key() => Contract.reason_missing(),
        Contract.allowed_values_key() => @side_effect_classes
      }
    )
  end

  defp invalid_side_effect_decision(tool, {:invalid, value}) do
    Decision.reject(
      EventContract.invalid_tool_metadata(),
      Contract.invalid_side_effect_message(),
      %{
        Contract.tool_key() => tool,
        Contract.field_key() => @side_effect_key,
        Contract.reason_key() => Contract.reason_invalid(),
        Contract.value_key() => value,
        Contract.allowed_values_key() => @side_effect_classes
      }
    )
  end

  defp invalid_side_effect_decision(tool, _reason), do: invalid_side_effect_decision(tool, :missing)

  defp non_empty_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp non_empty_string?(_value), do: false
end
