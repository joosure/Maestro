defmodule SymphonyWorkerDaemon.CapacityManager.TenantKey do
  @moduledoc false

  alias SymphonyWorkerDaemon.Protocol.Fields, as: ProtocolFields

  @caller_key ProtocolFields.caller()
  @owner_key ProtocolFields.owner()
  @tenant_id_key ProtocolFields.tenant_id()

  @spec from_attrs(map()) :: String.t()
  def from_attrs(attrs) when is_map(attrs) do
    caller = Map.get(attrs, :caller) || Map.get(attrs, @caller_key) || %{}
    owner = caller_value(caller, @owner_key) || "unknown_owner"
    tenant_id = caller_value(caller, @tenant_id_key) || "default_tenant"
    tenant_id <> ":" <> owner
  end

  defp caller_value(caller, key) when is_map(caller) and is_binary(key) do
    normalize_optional_string(Map.get(caller, key) || caller_atom_value(caller, key))
  end

  defp caller_value(_caller, _key), do: nil

  defp caller_atom_value(caller, @owner_key), do: Map.get(caller, :owner)
  defp caller_atom_value(caller, @tenant_id_key), do: Map.get(caller, :tenant_id)
  defp caller_atom_value(_caller, _key), do: nil

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil
end
