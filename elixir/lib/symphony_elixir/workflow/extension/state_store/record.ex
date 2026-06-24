defmodule SymphonyElixir.Workflow.Extension.StateStore.Record do
  @moduledoc """
  Stable platform envelope for workflow extension-owned state.

  The platform owns the envelope and storage identity. Extensions own the
  meaning and schema of `payload`; platform code treats it as opaque data.
  """

  alias SymphonyElixir.Workflow.Extension.StateStore.Record.{Error, Identity, Json}

  @schema_id "workflow.extension_state_record.v1"

  @record_fields [
    :id,
    :extension_id,
    :extension_version,
    :workflow_scope,
    :workflow_scope_key,
    :state_type,
    :state_key,
    :payload_schema,
    :payload,
    :expires_at_ms,
    :inserted_at,
    :updated_at
  ]

  @input_keys @record_fields ++ [:payload_json]
  @allowed_keys @input_keys
  @external_field_names Enum.map(@input_keys, &Atom.to_string/1)
  @external_key_map Map.new(@input_keys, &{Atom.to_string(&1), &1})

  @enforce_keys [
    :id,
    :extension_id,
    :workflow_scope,
    :workflow_scope_key,
    :state_type,
    :state_key,
    :payload
  ]
  defstruct @record_fields

  @type t :: %__MODULE__{
          id: String.t(),
          extension_id: String.t(),
          extension_version: String.t() | nil,
          workflow_scope: map(),
          workflow_scope_key: String.t(),
          state_type: String.t(),
          state_key: String.t(),
          payload_schema: String.t() | nil,
          payload: map(),
          expires_at_ms: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec schema_id() :: String.t()
  def schema_id, do: @schema_id

  @spec record_fields() :: [atom()]
  def record_fields, do: @record_fields

  @spec input_keys() :: [atom()]
  def input_keys, do: @input_keys

  @spec external_field_names() :: [String.t()]
  def external_field_names, do: @external_field_names

  @spec new(map()) :: {:ok, t()} | {:error, map()}
  def new(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    with :ok <- validate_known_keys(attrs),
         {:ok, extension_id} <- required_string(attrs, :extension_id),
         {:ok, workflow_scope} <- required_json_map(attrs, :workflow_scope, :atom_or_string_keys),
         {:ok, state_type} <- required_string(attrs, :state_type),
         {:ok, state_key} <- required_string(attrs, :state_key),
         {:ok, payload} <- required_json_map(payload_attrs(attrs), :payload, :string_keys),
         {:ok, extension_version} <- optional_string(attrs, :extension_version),
         {:ok, payload_schema} <- optional_string(attrs, :payload_schema),
         {:ok, expires_at_ms} <- optional_integer(attrs, :expires_at_ms),
         {:ok, workflow_scope_key} <- scope_key(attrs, workflow_scope),
         {:ok, id} <- record_id(attrs, extension_id, workflow_scope_key, state_type, state_key) do
      {:ok,
       %__MODULE__{
         id: id,
         extension_id: extension_id,
         extension_version: extension_version,
         workflow_scope: workflow_scope,
         workflow_scope_key: workflow_scope_key,
         state_type: state_type,
         state_key: state_key,
         payload_schema: payload_schema,
         payload: payload,
         expires_at_ms: expires_at_ms,
         inserted_at: Map.get(attrs, :inserted_at),
         updated_at: Map.get(attrs, :updated_at)
       }}
    end
  end

  def new(attrs), do: {:error, invalid(:record_not_a_map, attrs)}

  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, record} -> record
      {:error, reason} -> raise ArgumentError, Error.format(reason)
    end
  end

  @spec scope_key(map()) :: {:ok, String.t()} | {:error, map()}
  def scope_key(scope) when is_map(scope), do: Identity.scope_key(scope)

  @spec stale?(t(), integer()) :: boolean()
  def stale?(%__MODULE__{expires_at_ms: nil}, _now_ms), do: false
  def stale?(%__MODULE__{expires_at_ms: expires_at_ms}, now_ms), do: expires_at_ms <= now_ms

  defp normalize_keys(attrs) do
    Enum.into(attrs, %{}, fn {key, value} ->
      {Map.get(@external_key_map, key, key), value}
    end)
  end

  defp validate_known_keys(attrs) do
    unknown_keys = attrs |> Map.keys() |> Enum.reject(&(&1 in @allowed_keys))

    case unknown_keys do
      [] -> :ok
      keys -> {:error, invalid(:unknown_fields, keys)}
    end
  end

  defp payload_attrs(%{payload: _payload} = attrs), do: attrs
  defp payload_attrs(%{payload_json: payload_json} = attrs), do: Map.put(attrs, :payload, payload_json)
  defp payload_attrs(attrs), do: attrs

  defp required_string(attrs, key) do
    attrs
    |> Map.get(key)
    |> non_empty_string(key)
  end

  defp optional_string(attrs, key) do
    case Map.get(attrs, key) do
      nil -> {:ok, nil}
      value -> non_empty_string(value, key)
    end
  end

  defp non_empty_string(value, key) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, invalid({:empty_string, key}, value)}
      trimmed -> {:ok, trimmed}
    end
  end

  defp non_empty_string(value, key), do: {:error, invalid({:invalid_string, key}, value)}

  defp required_json_map(attrs, key, key_policy) do
    case Map.get(attrs, key) do
      value when is_struct(value) ->
        {:error, invalid({:invalid_json_map, key}, value)}

      value when is_map(value) ->
        if Json.compatible?(value, key_policy) do
          {:ok, value}
        else
          {:error, invalid({:invalid_json_value, key}, value)}
        end

      value ->
        {:error, invalid({:invalid_map, key}, value)}
    end
  end

  defp optional_integer(attrs, key) do
    case Map.get(attrs, key) do
      nil -> {:ok, nil}
      value when is_integer(value) -> {:ok, value}
      value -> {:error, invalid({:invalid_integer, key}, value)}
    end
  end

  defp scope_key(%{workflow_scope_key: workflow_scope_key}, workflow_scope) do
    case non_empty_string(workflow_scope_key, :workflow_scope_key) do
      {:ok, value} ->
        case Identity.scope_key(workflow_scope) do
          {:ok, expected} ->
            if value == expected do
              {:ok, value}
            else
              {:error, invalid(:workflow_scope_key_mismatch, workflow_scope_key)}
            end

          {:error, reason} ->
            {:error, canonical_error(reason)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp scope_key(_attrs, workflow_scope) do
    case Identity.scope_key(workflow_scope) do
      {:ok, workflow_scope_key} -> {:ok, workflow_scope_key}
      {:error, reason} -> {:error, canonical_error(reason)}
    end
  end

  defp record_id(%{id: id}, extension_id, workflow_scope_key, state_type, state_key) do
    expected = Identity.record_id(extension_id, workflow_scope_key, state_type, state_key)

    case non_empty_string(id, :id) do
      {:ok, ^expected} -> {:ok, expected}
      {:ok, _other} -> {:error, invalid(:id_mismatch, id)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp record_id(_attrs, extension_id, workflow_scope_key, state_type, state_key) do
    {:ok, Identity.record_id(extension_id, workflow_scope_key, state_type, state_key)}
  end

  defp invalid(reason, value) do
    Error.invalid(reason, value)
  end

  defp canonical_error(reason) do
    Error.canonical(reason)
  end
end
