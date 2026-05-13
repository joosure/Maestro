defmodule SymphonyElixir.Agent.Quota.Snapshot do
  @moduledoc false

  @type status :: :unknown | :healthy | :limited | :exhausted | :degraded | :unsupported

  @type t :: %__MODULE__{
          provider_kind: String.t(),
          credential_ref_summary: String.t() | nil,
          account_id_summary: String.t() | nil,
          status: status(),
          remaining: non_neg_integer() | nil,
          limit: non_neg_integer() | nil,
          reset_at: DateTime.t() | nil,
          retry_after_ms: non_neg_integer() | nil,
          observed_at: DateTime.t(),
          expires_at: DateTime.t() | nil,
          details: map()
        }

  defstruct provider_kind: nil,
            credential_ref_summary: nil,
            account_id_summary: nil,
            status: :unknown,
            remaining: nil,
            limit: nil,
            reset_at: nil,
            retry_after_ms: nil,
            observed_at: nil,
            expires_at: nil,
            details: %{}

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      provider_kind: optional_string(value(attrs, :provider_kind)),
      credential_ref_summary: optional_string(value(attrs, :credential_ref_summary)),
      account_id_summary: optional_string(value(attrs, :account_id_summary)),
      status: normalize_status(value(attrs, :status)),
      remaining: normalize_non_negative_integer(value(attrs, :remaining)),
      limit: normalize_non_negative_integer(value(attrs, :limit)),
      reset_at: normalize_datetime(value(attrs, :reset_at)),
      retry_after_ms: normalize_non_negative_integer(value(attrs, :retry_after_ms)),
      observed_at: normalize_datetime(value(attrs, :observed_at)) || DateTime.utc_now(),
      expires_at: normalize_datetime(value(attrs, :expires_at)),
      details: normalize_map(value(attrs, :details))
    }
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp normalize_status(status) when status in [:unknown, :healthy, :limited, :exhausted, :degraded, :unsupported], do: status
  defp normalize_status("healthy"), do: :healthy
  defp normalize_status("limited"), do: :limited
  defp normalize_status("exhausted"), do: :exhausted
  defp normalize_status("degraded"), do: :degraded
  defp normalize_status("unsupported"), do: :unsupported
  defp normalize_status(_status), do: :unknown

  defp normalize_non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp normalize_non_negative_integer(_value), do: nil

  defp normalize_datetime(%DateTime{} = datetime), do: datetime
  defp normalize_datetime(_value), do: nil

  defp optional_string(nil), do: nil

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp optional_string(_value), do: nil

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_map), do: %{}
end
