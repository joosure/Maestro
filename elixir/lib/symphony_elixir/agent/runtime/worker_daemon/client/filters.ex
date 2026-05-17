defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.Client.Filters do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.Target
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.Client.Connection
  alias SymphonyWorkerDaemon.Auth.Defaults, as: AuthDefaults
  alias SymphonyWorkerDaemon.Protocol.Fields, as: ProtocolFields

  @owner_key ProtocolFields.owner()
  @tenant_id_key ProtocolFields.tenant_id()
  @run_id_key ProtocolFields.run_id()
  @status_key ProtocolFields.status()
  @after_event_id_key ProtocolFields.after_event_id()
  @limit_key ProtocolFields.limit()

  @spec session_filters(Target.t(), keyword()) :: map()
  def session_filters(%Target{} = target, opts) do
    explicit_filters = Keyword.get(opts, :worker_daemon_session_filters, %{})

    %{
      @owner_key => Keyword.get(opts, :worker_daemon_owner, AuthDefaults.default_owner()),
      @tenant_id_key => Keyword.get(opts, :tenant_id) || Connection.metadata_value(target.metadata, :tenant_id),
      @run_id_key => Keyword.get(opts, :run_id) || Connection.metadata_value(target.metadata, :run_id),
      @status_key => Keyword.get(opts, :status)
    }
    |> Map.merge(normalize_filter_map(explicit_filters))
    |> Enum.reject(fn {_key, value} -> is_nil(normalize_optional_string(value)) end)
    |> Map.new(fn {key, value} -> {key, normalize_optional_string(value)} end)
  end

  @spec session_event_filters(keyword()) :: map()
  def session_event_filters(opts) when is_list(opts) do
    %{
      @after_event_id_key => Keyword.get(opts, :after_event_id),
      @limit_key => Keyword.get(opts, :limit)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(normalize_optional_string(value)) end)
    |> Map.new(fn {key, value} -> {key, normalize_optional_string(value)} end)
  end

  @spec put_optional_filter(map(), String.t(), term()) :: map()
  def put_optional_filter(filters, key, value) when is_map(filters) and is_binary(key) do
    case normalize_optional_string(value) do
      nil -> filters
      normalized_value -> Map.put(filters, key, normalized_value)
    end
  end

  defp normalize_filter_map(filters) when is_map(filters) do
    filters
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case normalize_filter_key(key) do
        nil -> acc
        normalized_key -> Map.put(acc, normalized_key, value)
      end
    end)
  end

  defp normalize_filter_map(filters) when is_list(filters), do: filters |> Map.new() |> normalize_filter_map()
  defp normalize_filter_map(_filters), do: %{}

  defp normalize_filter_key(key) when key in [@owner_key, :owner], do: @owner_key
  defp normalize_filter_key(key) when key in [@tenant_id_key, :tenant_id], do: @tenant_id_key
  defp normalize_filter_key(key) when key in [@run_id_key, :run_id], do: @run_id_key
  defp normalize_filter_key(key) when key in [@status_key, :status], do: @status_key
  defp normalize_filter_key(_key), do: nil

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
