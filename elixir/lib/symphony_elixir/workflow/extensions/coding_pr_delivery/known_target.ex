defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget do
  @moduledoc """
  Coding PR Delivery's stable domain model for an issue's known change-proposal target.

  The platform persists this record only as plugin-owned state. This module owns
  the business identity and merge rules; storage, registry lifecycle, and
  provider/tracker adapters stay outside this value object.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Clock
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Error
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.JsonValue
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Reference

  @type json_value :: JsonValue.t()

  defstruct [
    :issue_id,
    :tracker_kind,
    :repo_provider_kind,
    :repository,
    :number,
    :url,
    :branch,
    :head_sha,
    :last_observed_signature,
    :last_observed_at,
    :last_enqueued_at_ms,
    :registered_at_ms,
    :updated_at_ms
  ]

  @type t :: %__MODULE__{
          issue_id: String.t(),
          tracker_kind: String.t() | nil,
          repo_provider_kind: String.t() | nil,
          repository: String.t() | nil,
          number: String.t() | nil,
          url: String.t() | nil,
          branch: String.t() | nil,
          head_sha: String.t() | nil,
          last_observed_signature: json_value(),
          last_observed_at: DateTime.t() | nil,
          last_enqueued_at_ms: integer() | nil,
          registered_at_ms: integer() | nil,
          updated_at_ms: integer() | nil
        }

  @spec new(term(), term()) :: {:ok, t()} | {:error, map()}
  def new(attrs, opts \\ []) do
    with {:ok, opts} <- validate_opts(opts),
         :ok <- validate_attrs(attrs),
         {:ok, now_ms} <- Clock.now_ms(opts),
         {:ok, signature} <- observed_signature(attrs) do
      reference = Reference.from_map(attrs) || %Reference{}
      target = build(attrs, reference, signature, now_ms)

      validate_target(target)
    end
  end

  @spec merge(term(), term(), term()) :: {:ok, t()} | {:error, map()}
  def merge(existing, incoming, opts \\ []) do
    with {:ok, opts} <- validate_opts(opts),
         :ok <- validate_record(existing, :existing),
         :ok <- validate_record(incoming, :incoming),
         {:ok, now_ms} <- Clock.now_ms(opts) do
      {:ok, merge_records(existing, incoming, now_ms)}
    end
  end

  @spec reference(t()) :: Reference.t()
  def reference(%__MODULE__{} = target) do
    Reference.from_target(target)
  end

  defp build(attrs, %Reference{} = reference, signature, now_ms) do
    %__MODULE__{
      issue_id: string_value(attrs, Fields.issue_id()),
      tracker_kind: string_value(attrs, Fields.tracker_kind()),
      repo_provider_kind: string_value(attrs, Fields.repo_provider_kind()),
      repository: string_value(attrs, Fields.repository()),
      number: reference.number,
      url: reference.url,
      branch: reference.branch,
      head_sha: string_value(attrs, Fields.head_sha()),
      last_observed_signature: signature,
      last_observed_at: observed_at(attrs),
      last_enqueued_at_ms: integer_value(attrs, Fields.last_enqueued_at_ms()),
      registered_at_ms: integer_value(attrs, Fields.registered_at_ms()) || now_ms,
      updated_at_ms: integer_value(attrs, Fields.updated_at_ms()) || now_ms
    }
  end

  defp merge_records(%__MODULE__{} = existing, %__MODULE__{} = incoming, now_ms) when is_integer(now_ms) do
    %__MODULE__{
      existing
      | tracker_kind: coalesce_nil(incoming.tracker_kind, existing.tracker_kind),
        repo_provider_kind: coalesce_nil(incoming.repo_provider_kind, existing.repo_provider_kind),
        repository: coalesce_nil(incoming.repository, existing.repository),
        number: coalesce_nil(incoming.number, existing.number),
        url: coalesce_nil(incoming.url, existing.url),
        branch: coalesce_nil(incoming.branch, existing.branch),
        head_sha: coalesce_nil(incoming.head_sha, existing.head_sha),
        last_observed_signature: coalesce_nil(incoming.last_observed_signature, existing.last_observed_signature),
        last_observed_at: coalesce_nil(incoming.last_observed_at, existing.last_observed_at),
        last_enqueued_at_ms: coalesce_nil(incoming.last_enqueued_at_ms, existing.last_enqueued_at_ms),
        updated_at_ms: now_ms
    }
  end

  defp coalesce_nil(nil, fallback), do: fallback
  defp coalesce_nil(value, _fallback), do: value

  defp validate_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: {:ok, opts}, else: {:error, Error.invalid_options(opts)}
  end

  defp validate_opts(opts), do: {:error, Error.invalid_options(opts)}

  defp validate_attrs(attrs) when is_map(attrs), do: :ok
  defp validate_attrs(attrs), do: {:error, Error.invalid_attrs(attrs)}

  defp validate_record(%__MODULE__{}, _role), do: :ok
  defp validate_record(value, role), do: {:error, Error.invalid_record(value, role)}

  defp validate_target(%__MODULE__{} = target) do
    cond do
      is_nil(target.issue_id) ->
        {:error, Error.missing_issue_id()}

      is_nil(target.number) and is_nil(target.url) and is_nil(target.branch) ->
        {:error, Error.missing_reference()}

      true ->
        {:ok, target}
    end
  end

  defp observed_signature(attrs) do
    case JsonValue.normalize(value(attrs, Fields.last_observed_signature())) do
      {:ok, signature} -> {:ok, signature}
      {:error, reason} -> {:error, Error.invalid_signature(reason)}
    end
  end

  defp observed_at(attrs) do
    case value(attrs, Fields.last_observed_at()) do
      %DateTime{} = datetime -> datetime
      _value -> nil
    end
  end

  defp string_value(map, key) when is_map(map) and is_binary(key) do
    map
    |> value(key)
    |> normalize_string()
  end

  defp integer_value(map, key) when is_map(map) and is_binary(key) do
    case value(map, key) do
      integer when is_integer(integer) -> integer
      _value -> nil
    end
  end

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key)
  end

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(_value), do: nil
end
