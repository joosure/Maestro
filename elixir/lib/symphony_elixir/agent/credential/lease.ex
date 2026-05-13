defmodule SymphonyElixir.Agent.Credential.Lease do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t(),
          provider_kind: String.t(),
          credential_ref_summary: String.t(),
          account_id: String.t() | nil,
          expires_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct id: nil,
            provider_kind: nil,
            credential_ref_summary: nil,
            account_id: nil,
            expires_at: nil,
            metadata: %{}

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: optional_string(value(attrs, :id)),
      provider_kind: optional_string(value(attrs, :provider_kind)),
      credential_ref_summary: optional_string(value(attrs, :credential_ref_summary)),
      account_id: optional_string(value(attrs, :account_id)),
      expires_at: normalize_datetime(value(attrs, :expires_at)),
      metadata: normalize_metadata(value(attrs, :metadata))
    }
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp optional_string(nil), do: nil

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp optional_string(_value), do: nil

  defp normalize_datetime(%DateTime{} = datetime), do: datetime
  defp normalize_datetime(_value), do: nil

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(_metadata), do: %{}
end
