defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.Scope do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics

  @missing_workflow_scope_error %{
    code: "missing_coding_pr_delivery_workflow_scope",
    message: "Coding PR Delivery known-target storage requires an explicit workflow scope.",
    reason: :missing_workflow_scope
  }

  @invalid_workflow_scope_error %{
    code: "invalid_coding_pr_delivery_workflow_scope",
    message: "Coding PR Delivery known-target storage requires a JSON-compatible workflow scope.",
    reason: :invalid_workflow_scope
  }

  @spec fetch(keyword()) :: {:ok, map()} | {:error, map()}
  def fetch(opts) do
    case Keyword.get(opts, :workflow_scope) do
      scope when is_map(scope) ->
        case normalize(scope) do
          {:ok, scope} -> {:ok, scope}
          {:error, reason} -> {:error, invalid_workflow_scope_error(reason)}
        end

      _scope ->
        {:error, @missing_workflow_scope_error}
    end
  end

  @spec normalize(map()) :: {:ok, map()} | {:error, term()}
  def normalize(map) when is_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with {:ok, key} <- json_key(key),
           {:ok, value} <- json_value(value) do
        {:cont, {:ok, Map.put(acc, key, value)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp json_value(value) when is_struct(value), do: invalid_workflow_scope_value(value)
  defp json_value(value) when is_map(value), do: normalize(value)

  defp json_value(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case json_value(value) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp json_value(value) when is_binary(value), do: {:ok, value}
  defp json_value(value) when is_boolean(value), do: {:ok, value}
  defp json_value(value) when is_integer(value), do: {:ok, value}
  defp json_value(value) when is_float(value), do: {:ok, value}
  defp json_value(nil), do: {:ok, nil}
  defp json_value(value), do: invalid_workflow_scope_value(value)

  defp json_key(key) when is_binary(key), do: {:ok, key}
  defp json_key(key), do: {:error, {:invalid_workflow_scope_key, Diagnostics.detailed_type_atom(key)}}

  defp invalid_workflow_scope_error(reason), do: Map.put(@invalid_workflow_scope_error, :reason, reason)

  defp invalid_workflow_scope_value(value), do: {:error, {:invalid_workflow_scope_value, Diagnostics.detailed_type_atom(value)}}
end
