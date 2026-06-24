defmodule SymphonyElixir.Storage.TableCatalog.Entry do
  @moduledoc """
  Normalized platform inventory record for one durable storage table.

  This struct is intentionally table-level only. Subsystem storage contracts own
  column identifiers, indexes, projection metadata, and state-machine meaning.
  """

  @field_keys [:backend, :owner, :table, :table_name, :contract_module, :payload_schema, :purpose]
  @allowed_keys @field_keys
  @external_field_names Enum.map(@field_keys, &Atom.to_string/1)
  @external_key_map Map.new(@field_keys, &{Atom.to_string(&1), &1})

  @enforce_keys [:backend, :owner, :table, :table_name, :contract_module, :purpose]
  defstruct @field_keys

  @type backend :: :sqlite

  @type t :: %__MODULE__{
          backend: backend(),
          owner: atom(),
          table: atom(),
          table_name: String.t(),
          contract_module: module(),
          payload_schema: String.t() | nil,
          purpose: String.t()
        }

  @spec field_keys() :: [atom()]
  def field_keys, do: @field_keys

  @spec external_field_names() :: [String.t()]
  def external_field_names, do: @external_field_names

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)
    validate_known_keys!(attrs)
    backend = backend!(Map.fetch!(attrs, :backend))
    table = table!(Map.fetch!(attrs, :table))
    table_name = table_name!(Map.get(attrs, :table_name), table)

    %__MODULE__{
      backend: backend,
      owner: owner!(Map.fetch!(attrs, :owner)),
      table: table,
      table_name: table_name,
      contract_module: contract_module!(Map.fetch!(attrs, :contract_module)),
      payload_schema: payload_schema!(Map.get(attrs, :payload_schema)),
      purpose: purpose!(Map.fetch!(attrs, :purpose))
    }
  end

  defp normalize_keys(attrs) do
    Enum.into(attrs, %{}, fn {key, value} ->
      {Map.get(@external_key_map, key, key), value}
    end)
  end

  defp validate_known_keys!(attrs) do
    unknown_keys = attrs |> Map.keys() |> Enum.reject(&(&1 in @allowed_keys))

    case unknown_keys do
      [] ->
        :ok

      keys ->
        raise ArgumentError,
              "storage catalog entry contains unsupported field(s): " <>
                Enum.map_join(keys, ", ", &inspect/1)
    end
  end

  defp backend!(:sqlite), do: :sqlite

  defp backend!(backend) do
    raise ArgumentError, "unsupported storage catalog backend #{inspect(backend)}"
  end

  defp table!(table) when is_atom(table) and not is_nil(table), do: table

  defp table!(table) do
    raise ArgumentError, "storage catalog table must be an atom, got #{inspect(table)}"
  end

  defp table_name!(nil, table), do: Atom.to_string(table)

  defp table_name!(table_name, _table) when is_binary(table_name) do
    case String.trim(table_name) do
      "" -> raise ArgumentError, "storage catalog table_name must be non-empty"
      trimmed -> trimmed
    end
  end

  defp table_name!(table_name, _table) do
    raise ArgumentError, "storage catalog table_name must be a string, got #{inspect(table_name)}"
  end

  defp owner!(owner) when is_atom(owner) and not is_nil(owner), do: owner

  defp owner!(owner) do
    raise ArgumentError, "storage catalog owner must be an atom, got #{inspect(owner)}"
  end

  defp contract_module!(module) when is_atom(module) and not is_nil(module), do: module

  defp contract_module!(module) do
    raise ArgumentError, "storage catalog contract_module must be a module atom, got #{inspect(module)}"
  end

  defp payload_schema!(nil), do: nil

  defp payload_schema!(payload_schema) when is_binary(payload_schema) do
    case String.trim(payload_schema) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp payload_schema!(payload_schema) do
    raise ArgumentError, "storage catalog payload_schema must be a string or nil, got #{inspect(payload_schema)}"
  end

  defp purpose!(purpose) when is_binary(purpose) do
    case String.trim(purpose) do
      "" -> raise ArgumentError, "storage catalog purpose must be non-empty"
      trimmed -> trimmed
    end
  end

  defp purpose!(purpose) do
    raise ArgumentError, "storage catalog purpose must be a string, got #{inspect(purpose)}"
  end
end
