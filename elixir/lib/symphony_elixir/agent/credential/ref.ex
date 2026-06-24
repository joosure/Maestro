defmodule SymphonyElixir.Agent.Credential.Ref do
  @moduledoc """
  Stable credential-reference formatter for managed agent credentials.

  This module owns the external `credential://provider/id` reference shape.
  Credential stores and higher-level workflow/profile code can share the same
  formatter without depending on storage-oriented credential store APIs.
  """

  @scheme "credential"

  @spec for_account(String.t(), String.t()) :: String.t()
  def for_account(provider_kind, account_id) when is_binary(provider_kind) and is_binary(account_id) do
    provider_kind = normalize_segment!(provider_kind, :provider_kind)
    account_id = normalize_segment!(account_id, :account_id)

    "#{@scheme}://#{provider_kind}/#{account_id}"
  end

  defp normalize_segment!(value, field) do
    value = String.trim(value)

    if value == "" or String.contains?(value, "/") do
      raise ArgumentError, "credential ref #{field} must be a non-empty path segment"
    end

    value
  end
end
