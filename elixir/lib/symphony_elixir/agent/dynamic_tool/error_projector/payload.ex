defmodule SymphonyElixir.Agent.DynamicTool.ErrorProjector.Payload do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.ErrorProjector.Contract
  alias SymphonyElixir.Agent.DynamicTool.Serializer
  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response

  @fallback_message "Dynamic tool execution failed."

  @spec provider_error(term(), term(), term(), String.t() | nil, boolean(), term(), keyword()) :: map()
  def provider_error(provider, operation, code, message, retryable?, details, opts \\ []) do
    %{
      Response.message_key() => message || @fallback_message,
      Response.code_key() => to_code(code),
      Contract.retryable_key() => retryable? == true
    }
    |> put_present(Contract.provider_key(), provider)
    |> put_present(Contract.operation_key(), operation_name(operation))
    |> put_present(Contract.status_key(), canonical_detail_value(details, Contract.status_key()))
    |> put_present(Contract.details_key(), public_details(details))
    |> put_present(Contract.exit_code_key(), Keyword.get(opts, :exit_code))
  end

  @spec local_error(term(), term(), String.t() | nil, term(), non_neg_integer(), boolean(), term()) :: map()
  def local_error(operation, code, message, path, exit_code, retryable?, details) do
    %{
      Response.message_key() => message || @fallback_message,
      Response.code_key() => to_code(code),
      Contract.retryable_key() => retryable?
    }
    |> put_present(Contract.operation_key(), operation_name(operation))
    |> put_present(Contract.path_key(), path)
    |> put_present(Contract.exit_code_key(), exit_code)
    |> put_present(Contract.status_key(), canonical_detail_value(details, Contract.status_key()))
    |> put_present(Contract.details_key(), public_details(details))
  end

  @spec public_details(term()) :: map() | nil
  def public_details(details) when is_map(details) do
    details
    |> normalize_public_detail_keys()
    |> Serializer.public_error_details()
  end

  def public_details(value) when is_binary(value) or is_number(value) or is_boolean(value) do
    %{Contract.value_key() => Serializer.json_safe_value(value)}
  end

  def public_details(_value), do: nil

  defp normalize_public_detail_keys(details) do
    allowed_keys = Contract.public_detail_keys()

    details
    |> Enum.flat_map(fn {key, value} ->
      with canonical_key when is_binary(canonical_key) <- public_detail_key(key),
           true <- canonical_key in allowed_keys do
        [{canonical_key, value}]
      else
        _ -> []
      end
    end)
    |> Map.new()
  end

  defp public_detail_key(key) when is_binary(key), do: key
  defp public_detail_key(key) when is_atom(key), do: Atom.to_string(key)
  defp public_detail_key(_key), do: nil

  defp canonical_detail_value(details, key) when is_map(details) and is_binary(key), do: Map.get(details, key)
  defp canonical_detail_value(_details, _key), do: nil

  defp operation_name(nil), do: nil
  defp operation_name(operation) when is_binary(operation), do: operation
  defp operation_name(operation) when is_atom(operation), do: Atom.to_string(operation)
  defp operation_name(operation), do: inspect(operation)

  defp to_code(nil), do: "unknown"
  defp to_code(code) when is_binary(code) and code != "", do: code
  defp to_code(code) when is_atom(code), do: Atom.to_string(code)
  defp to_code(code), do: inspect(code)

  defp put_present(payload, _key, nil), do: payload
  defp put_present(payload, _key, ""), do: payload
  defp put_present(payload, key, value), do: Map.put(payload, key, Serializer.json_safe_value(value))
end
