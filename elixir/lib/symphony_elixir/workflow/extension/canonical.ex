defmodule SymphonyElixir.Workflow.Extension.Canonical do
  @moduledoc """
  Canonical encoders for workflow-extension durable identity.

  Runtime workflow-config hashes and state-store scope keys use different
  versioned codecs for compatibility, but the encoding ownership stays in one
  platform mechanism module so future durable identity changes are explicit.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.ErrorCodes

  @runtime_config_hash_codec "workflow.extension.runtime_config_hash.v1"
  @state_store_scope_key_codec "workflow.extension.state_store_scope_key.v1"

  @type error :: %{
          required(:code) => String.t(),
          required(:message) => String.t(),
          required(:codec) => String.t(),
          required(:reason) => atom(),
          optional(:value_type) => atom() | nil
        }

  @spec runtime_config_hash(term()) :: {:ok, String.t()} | {:error, error()}
  def runtime_config_hash(value) do
    with {:ok, encoded} <- runtime_encode(value) do
      {:ok, hash_binary(@runtime_config_hash_codec, encoded)}
    end
  end

  @spec state_store_scope_key(term()) :: {:ok, String.t()} | {:error, error()}
  def state_store_scope_key(scope) do
    with {:ok, value} <- state_store_scope_value(scope) do
      {:ok, hash_binary(@state_store_scope_key_codec, :erlang.term_to_binary(value))}
    end
  end

  @spec runtime_config_hash_codec() :: String.t()
  def runtime_config_hash_codec, do: @runtime_config_hash_codec

  @spec state_store_scope_key_codec() :: String.t()
  def state_store_scope_key_codec, do: @state_store_scope_key_codec

  defp hash_binary(codec, encoded) do
    [codec, <<0>>, encoded]
    |> IO.iodata_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp runtime_encode(value) do
    with {:ok, encoded} <- runtime_value(value) do
      {:ok, IO.iodata_to_binary(encoded)}
    end
  end

  defp runtime_value(value) when is_struct(value),
    do: {:error, error(@runtime_config_hash_codec, :unsupported_runtime_config_value, value)}

  defp runtime_value(value) when is_map(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn {key, entry_value}, {:ok, acc} ->
      with {:ok, encoded_key} <- runtime_map_key(key),
           {:ok, encoded_value} <- runtime_encode(entry_value) do
        {:cont, {:ok, [{encoded_key, encoded_value} | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries} ->
        encoded_entries =
          entries
          |> Enum.sort()
          |> Enum.map(fn {key, entry_value} -> ["m:", key, "=>", entry_value] end)

        {:ok, ["%{", Enum.intersperse(encoded_entries, ","), "}"]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp runtime_value(values) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case runtime_encode(value) do
        {:ok, encoded} -> {:cont, {:ok, [encoded | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, ["[", values |> Enum.reverse() |> Enum.intersperse(","), "]"]}
      {:error, reason} -> {:error, reason}
    end
  end

  defp runtime_value(value) when is_tuple(value),
    do: {:error, error(@runtime_config_hash_codec, :unsupported_runtime_config_value, value)}

  defp runtime_value(value) when is_binary(value), do: {:ok, ["s:", Base.encode64(value)]}
  defp runtime_value(value) when is_atom(value), do: {:ok, ["a:", Atom.to_string(value)]}
  defp runtime_value(value) when is_integer(value), do: {:ok, ["i:", Integer.to_string(value)]}

  defp runtime_value(value) when is_float(value),
    do: {:ok, ["f:", :erlang.float_to_binary(value, [:short])]}

  defp runtime_value(value) when is_pid(value),
    do: {:error, error(@runtime_config_hash_codec, :unsupported_runtime_config_value, value)}

  defp runtime_value(value) when is_reference(value),
    do: {:error, error(@runtime_config_hash_codec, :unsupported_runtime_config_value, value)}

  defp runtime_value(value) when is_function(value),
    do: {:error, error(@runtime_config_hash_codec, :unsupported_runtime_config_value, value)}

  defp runtime_value(value),
    do: {:error, error(@runtime_config_hash_codec, :unsupported_runtime_config_value, value)}

  defp runtime_map_key(key) when is_binary(key), do: {:ok, ["s:", Base.encode64(key)]}
  defp runtime_map_key(key) when is_atom(key), do: {:ok, ["a:", Atom.to_string(key)]}

  defp runtime_map_key(key),
    do: {:error, error(@runtime_config_hash_codec, :unsupported_runtime_config_key, key)}

  defp state_store_scope_value(value) when is_struct(value),
    do: {:error, error(@state_store_scope_key_codec, :unsupported_state_store_scope_value, value)}

  defp state_store_scope_value(value) when is_map(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, acc} ->
      with {:ok, key} <- state_store_scope_key_part(key),
           {:ok, value} <- state_store_scope_value(value) do
        {:cont, {:ok, [{key, value} | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.sort_by(values, fn {key, _value} -> key end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp state_store_scope_value(values) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case state_store_scope_value(value) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp state_store_scope_value(value) when is_binary(value), do: {:ok, value}
  defp state_store_scope_value(value) when is_boolean(value), do: {:ok, value}
  defp state_store_scope_value(value) when is_integer(value), do: {:ok, value}
  defp state_store_scope_value(value) when is_float(value), do: {:ok, value}
  defp state_store_scope_value(nil), do: {:ok, nil}

  defp state_store_scope_value(value) when is_atom(value) and not is_nil(value),
    do: {:error, error(@state_store_scope_key_codec, :unsupported_state_store_scope_value, value)}

  defp state_store_scope_value(value),
    do: {:error, error(@state_store_scope_key_codec, :unsupported_state_store_scope_value, value)}

  defp state_store_scope_key_part(key) when is_binary(key), do: {:ok, key}
  defp state_store_scope_key_part(key) when is_atom(key), do: {:ok, Atom.to_string(key)}

  defp state_store_scope_key_part(key),
    do: {:error, error(@state_store_scope_key_codec, :unsupported_state_store_scope_key, key)}

  defp error(codec, reason, value) do
    %{
      code: ErrorCodes.invalid_canonical_identity(),
      message: "Workflow extension canonical durable identity input is invalid.",
      codec: codec,
      reason: reason,
      value_type: Diagnostics.detailed_type_atom(value)
    }
  end
end
