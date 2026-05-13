defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.Endpoint do
  @moduledoc false

  @type validation_error :: {:worker_daemon_endpoint_invalid, map()}

  @spec normalize(term()) :: String.t() | nil
  def normalize(value) do
    case normalize_optional_string(value) do
      nil -> nil
      endpoint -> String.trim_trailing(endpoint, "/")
    end
  end

  @spec normalize_validated(term()) :: {:ok, String.t()} | {:error, :worker_daemon_endpoint_missing | validation_error()}
  def normalize_validated(value) do
    case normalize(value) do
      nil -> {:error, :worker_daemon_endpoint_missing}
      endpoint -> validate_normalized(endpoint)
    end
  end

  @spec safe(term()) :: String.t() | nil
  def safe(nil), do: nil

  def safe(value) when is_binary(value) do
    value
    |> URI.parse()
    |> safe_uri(value)
  end

  def safe(value), do: inspect(value, limit: 10, printable_limit: 200)

  defp validate_normalized(endpoint) when is_binary(endpoint) do
    uri = URI.parse(endpoint)

    cond do
      uri.scheme not in ["http", "https"] ->
        invalid(endpoint, "must use http or https scheme")

      not is_binary(uri.host) or uri.host == "" ->
        invalid(endpoint, "must include a host")

      is_binary(uri.userinfo) ->
        invalid(endpoint, "must not include userinfo")

      is_binary(uri.query) ->
        invalid(endpoint, "must not include a query string")

      is_binary(uri.fragment) ->
        invalid(endpoint, "must not include a fragment")

      true ->
        {:ok, endpoint}
    end
  end

  defp invalid(endpoint, reason) when is_binary(endpoint) and is_binary(reason) do
    {:error,
     {:worker_daemon_endpoint_invalid,
      %{
        endpoint: safe(endpoint),
        reason: reason
      }}}
  end

  defp safe_uri(%URI{scheme: scheme, host: host} = uri, _original)
       when is_binary(scheme) and is_binary(host) do
    scheme <> "://" <> host <> safe_port(uri) <> safe_path(uri)
  end

  defp safe_uri(_uri, original) do
    original
    |> String.split(["?", "#"], parts: 2)
    |> List.first()
  end

  defp safe_port(%URI{scheme: "http", port: 80}), do: ""
  defp safe_port(%URI{scheme: "https", port: 443}), do: ""
  defp safe_port(%URI{port: nil}), do: ""
  defp safe_port(%URI{port: port}) when is_integer(port), do: ":" <> Integer.to_string(port)

  defp safe_path(%URI{path: nil}), do: ""
  defp safe_path(%URI{path: ""}), do: ""
  defp safe_path(%URI{path: path}) when is_binary(path), do: path

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
