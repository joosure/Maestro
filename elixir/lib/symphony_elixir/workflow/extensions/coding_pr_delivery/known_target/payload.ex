defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Payload do
  @moduledoc """
  Stable payload codec for Coding PR Delivery known-target state.

  The platform `Workflow.Extension.StateStore` owns the durable envelope. This
  module owns the business payload shape and keeps it JSON-compatible before it
  crosses the extension-state boundary.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.JsonValue

  @schema_id "change_proposal.known_target.v1"
  @invalid_payload_code "invalid_coding_pr_delivery_known_target_payload"
  @invalid_payload_message "Coding PR Delivery known-target payload is invalid."

  @spec schema_id() :: String.t()
  def schema_id, do: @schema_id

  @spec to_map(KnownTarget.t()) :: {:ok, map()} | {:error, map()}
  def to_map(%KnownTarget{} = target) do
    case JsonValue.normalize(target.last_observed_signature) do
      {:ok, signature} ->
        {:ok,
         %{
           Fields.issue_id() => target.issue_id,
           Fields.tracker_kind() => target.tracker_kind,
           Fields.repo_provider_kind() => target.repo_provider_kind,
           Fields.repository() => target.repository,
           Fields.number() => target.number,
           Fields.url() => target.url,
           Fields.branch() => target.branch,
           Fields.head_sha() => target.head_sha,
           Fields.last_observed_signature() => signature,
           Fields.last_observed_at() => datetime_value(target.last_observed_at),
           Fields.last_enqueued_at_ms() => target.last_enqueued_at_ms,
           Fields.registered_at_ms() => target.registered_at_ms,
           Fields.updated_at_ms() => target.updated_at_ms
         }
         |> Map.reject(fn {_key, value} -> is_nil(value) end)}

      {:error, reason} ->
        {:error, invalid(reason)}
    end
  end

  @spec from_map(term(), term()) :: {:ok, KnownTarget.t()} | {:error, term()}
  def from_map(payload, opts \\ [])

  def from_map(payload, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      decode_payload(payload, opts)
    else
      {:error, invalid({:invalid_options, Diagnostics.detailed_type_atom(opts)})}
    end
  end

  def from_map(_payload, opts), do: {:error, invalid({:invalid_options, Diagnostics.detailed_type_atom(opts)})}

  defp decode_payload(payload, opts) when is_map(payload) do
    with {:ok, normalized_payload} <- normalize_payload(payload) do
      KnownTarget.new(normalized_payload, opts)
    end
  end

  defp decode_payload(payload, _opts), do: {:error, invalid({:invalid_payload, Diagnostics.detailed_type_atom(payload)})}

  defp normalize_payload(payload) when is_map(payload) do
    with {:ok, payload} <- normalize_observed_at(payload),
         {:ok, payload} <- normalize_signature(payload) do
      {:ok, payload}
    end
  end

  defp normalize_observed_at(payload) do
    key = Fields.last_observed_at()

    case Map.fetch(payload, key) do
      :error ->
        {:ok, payload}

      {:ok, nil} ->
        {:ok, payload}

      {:ok, %DateTime{}} ->
        {:error, invalid({:invalid_last_observed_at, :struct})}

      {:ok, value} when is_binary(value) ->
        decode_observed_at(payload, key, value)

      {:ok, value} ->
        {:error, invalid({:invalid_last_observed_at, Diagnostics.detailed_type_atom(value)})}
    end
  end

  defp decode_observed_at(payload, key, value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, Map.put(payload, key, datetime)}
      _error -> {:error, invalid({:invalid_last_observed_at, :invalid_iso8601})}
    end
  end

  defp normalize_signature(payload) do
    key = Fields.last_observed_signature()

    case Map.fetch(payload, key) do
      :error ->
        {:ok, payload}

      {:ok, value} ->
        case JsonValue.normalize(value) do
          {:ok, normalized} ->
            {:ok, Map.put(payload, key, normalized)}

          {:error, reason} ->
            {:error, invalid({:invalid_last_observed_signature, reason})}
        end
    end
  end

  defp datetime_value(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp datetime_value(_value), do: nil

  defp invalid(reason) do
    %{
      code: @invalid_payload_code,
      message: @invalid_payload_message,
      reason: reason
    }
  end
end
