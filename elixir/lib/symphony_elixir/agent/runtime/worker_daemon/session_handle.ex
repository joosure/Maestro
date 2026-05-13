defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.SessionHandle do
  @moduledoc false

  alias SymphonyElixir.Observability.Redaction

  @redacted "[REDACTED]"
  @default_client Module.concat(["SymphonyElixir", "Agent", "Runtime", "WorkerDaemon", "Client"])

  @type t :: %__MODULE__{
          endpoint: String.t(),
          token: String.t() | nil,
          session_id: String.t(),
          worker_id: String.t() | nil,
          daemon_instance_id: String.t() | nil,
          lease_id: String.t() | nil,
          client: module(),
          metadata: map()
        }

  defstruct endpoint: nil,
            token: nil,
            session_id: nil,
            worker_id: nil,
            daemon_instance_id: nil,
            lease_id: nil,
            client: @default_client,
            metadata: %{}

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      endpoint: string_value(attrs, :endpoint),
      token: string_value(attrs, :token),
      session_id: string_value(attrs, :session_id),
      worker_id: string_value(attrs, :worker_id),
      daemon_instance_id: string_value(attrs, :daemon_instance_id),
      lease_id: string_value(attrs, :lease_id),
      client: module_value(attrs, :client, @default_client),
      metadata: map_value(attrs, :metadata)
    }
  end

  @spec send_input(t(), iodata(), keyword()) :: boolean()
  def send_input(%__MODULE__{client: client} = handle, data, opts \\ []) do
    case client.send_input(handle, data, opts) do
      :ok -> true
      {:ok, _payload} -> true
      {:error, _reason} -> false
      _other -> false
    end
  end

  @spec stop(t(), keyword()) :: :ok | {:error, term()}
  def stop(%__MODULE__{client: client} = handle, opts \\ []) do
    client.stop_session(handle, opts)
  end

  @spec cleanup(t(), keyword()) :: :ok | {:error, term()}
  def cleanup(%__MODULE__{client: client} = handle, opts \\ []) do
    client.cleanup_session(handle, opts)
  end

  @spec alive?(t()) :: boolean()
  def alive?(%__MODULE__{client: client} = handle) do
    case client.session_status(handle, []) do
      {:ok, status} when is_binary(status) -> not SymphonyWorkerDaemon.Protocol.terminal_status?(status)
      _other -> false
    end
  end

  @spec safe_metadata(t()) :: map()
  def safe_metadata(%__MODULE__{} = handle) do
    safe_fields =
      %{
        worker_daemon_session_id: handle.session_id,
        worker_daemon_worker_id: handle.worker_id,
        worker_daemon_instance_id: handle.daemon_instance_id,
        worker_daemon_lease_id: handle.lease_id
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    handle.metadata
    |> safe_extra_metadata()
    |> Map.merge(safe_fields)
  end

  defp string_value(attrs, key) when is_map(attrs) do
    attrs
    |> value(key)
    |> normalize_optional_string()
  end

  defp module_value(attrs, key, default) when is_map(attrs) do
    case value(attrs, key) do
      module when is_atom(module) -> module
      _other -> default
    end
  end

  defp map_value(attrs, key) when is_map(attrs) do
    case value(attrs, key) do
      map when is_map(map) -> map
      _other -> %{}
    end
  end

  defp safe_extra_metadata(metadata) when is_map(metadata) do
    Map.new(metadata, fn {key, value} ->
      if sensitive_metadata_key?(key) do
        {key, @redacted}
      else
        {key, redact_metadata_value(value)}
      end
    end)
  end

  defp safe_extra_metadata(_metadata), do: %{}

  defp redact_metadata_value(value) when is_binary(value), do: Redaction.redact_string(value)
  defp redact_metadata_value(value) when is_map(value), do: safe_extra_metadata(value)
  defp redact_metadata_value(value) when is_list(value), do: Enum.map(value, &redact_metadata_value/1)
  defp redact_metadata_value(value), do: value

  defp sensitive_metadata_key?(key) do
    key
    |> metadata_key_to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/u, "")
    |> sensitive_normalized_key?()
  end

  defp metadata_key_to_string(key) when is_binary(key), do: key
  defp metadata_key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp metadata_key_to_string(key) when is_integer(key), do: Integer.to_string(key)
  defp metadata_key_to_string(key), do: inspect(key, limit: 10, printable_limit: 100)

  defp sensitive_normalized_key?("token"), do: true
  defp sensitive_normalized_key?("authorization"), do: true
  defp sensitive_normalized_key?("password"), do: true
  defp sensitive_normalized_key?("secret"), do: true

  defp sensitive_normalized_key?(key) when is_binary(key) do
    String.ends_with?(key, "token") or
      Enum.any?(["authorization", "password", "secret", "credential"], &String.contains?(key, &1))
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

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
