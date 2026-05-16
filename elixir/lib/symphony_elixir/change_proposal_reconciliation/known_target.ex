defmodule SymphonyElixir.ChangeProposalReconciliation.KnownTarget do
  @moduledoc false

  alias SymphonyElixir.ChangeProposalReconciliation.KnownTarget.Fields

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
          last_observed_signature: term(),
          last_observed_at: DateTime.t() | nil,
          last_enqueued_at_ms: integer() | nil,
          registered_at_ms: integer() | nil,
          updated_at_ms: integer() | nil
        }

  @spec new(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.monotonic_time(:millisecond) end)

    target = %__MODULE__{
      issue_id: string_value(attrs, Fields.issue_id()),
      tracker_kind: string_value(attrs, Fields.tracker_kind()),
      repo_provider_kind: string_value(attrs, Fields.repo_provider_kind()),
      repository: string_value(attrs, Fields.repository()),
      number:
        string_value(attrs, Fields.number()) ||
          string_value(attrs, Fields.change_proposal_id()) ||
          number_from_url(string_value(attrs, Fields.url())),
      url: string_value(attrs, Fields.url()),
      branch: string_value(attrs, Fields.branch()),
      head_sha: string_value(attrs, Fields.head_sha()),
      last_observed_signature: value(attrs, Fields.last_observed_signature()),
      last_observed_at: observed_at(attrs),
      last_enqueued_at_ms: integer_value(attrs, Fields.last_enqueued_at_ms()),
      registered_at_ms: integer_value(attrs, Fields.registered_at_ms()) || now_ms,
      updated_at_ms: integer_value(attrs, Fields.updated_at_ms()) || now_ms
    }

    cond do
      is_nil(target.issue_id) ->
        {:error, {:invalid_known_target, :missing_issue_id}}

      is_nil(target.number) and is_nil(target.url) and is_nil(target.branch) ->
        {:error, {:invalid_known_target, :missing_change_proposal_reference}}

      true ->
        {:ok, target}
    end
  end

  @spec merge(t(), t(), keyword()) :: t()
  def merge(%__MODULE__{} = existing, %__MODULE__{} = incoming, opts \\ []) when is_list(opts) do
    now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.monotonic_time(:millisecond) end)

    %__MODULE__{
      existing
      | tracker_kind: incoming.tracker_kind || existing.tracker_kind,
        repo_provider_kind: incoming.repo_provider_kind || existing.repo_provider_kind,
        repository: incoming.repository || existing.repository,
        number: incoming.number || existing.number,
        url: incoming.url || existing.url,
        branch: incoming.branch || existing.branch,
        head_sha: incoming.head_sha || existing.head_sha,
        last_observed_signature: incoming.last_observed_signature || existing.last_observed_signature,
        last_observed_at: incoming.last_observed_at || existing.last_observed_at,
        last_enqueued_at_ms: incoming.last_enqueued_at_ms || existing.last_enqueued_at_ms,
        updated_at_ms: now_ms
    }
  end

  @spec reference(t()) :: map()
  def reference(%__MODULE__{} = target) do
    %{
      number: target.number,
      url: target.url,
      branch: target.branch
    }
  end

  defp observed_at(attrs) do
    case value(attrs, Fields.last_observed_at()) do
      %DateTime{} = datetime -> datetime
      _value -> nil
    end
  end

  defp number_from_url(nil), do: nil

  defp number_from_url(url) when is_binary(url) do
    with %URI{path: path} when is_binary(path) <- URI.parse(url),
         [number | _rest] <- path |> String.split("/", trim: true) |> Enum.reverse(),
         true <- String.match?(number, ~r/^\d+$/) do
      number
    else
      _other -> nil
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
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
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
