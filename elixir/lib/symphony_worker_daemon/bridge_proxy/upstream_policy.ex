defmodule SymphonyWorkerDaemon.BridgeProxy.UpstreamPolicy do
  @moduledoc false

  alias SymphonyElixir.Platform.DynamicToolBridgeContract

  @base_path DynamicToolBridgeContract.base_path()

  @spec base_url(map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def base_url(%{"symphony_base_url" => base_url}, opts) when is_binary(base_url) and is_list(opts) do
    case String.trim(base_url) do
      "" -> {:error, :dynamic_tool_bridge_upstream_base_url_missing}
      value -> validate_base_url(value, opts)
    end
  end

  def base_url(_bridge_spec, _opts), do: {:error, :dynamic_tool_bridge_upstream_base_url_missing}

  @spec prepare_allowed_upstreams([term()]) :: {:ok, [String.t()]} | {:error, term()}
  def prepare_allowed_upstreams(entries) when is_list(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case normalize_base_url(entry) do
        {:ok, base_url} -> {:cont, {:ok, [base_url | acc]}}
        {:error, reason} -> {:halt, {:error, {:invalid_dynamic_tool_bridge_allowed_upstream, entry, reason}}}
      end
    end)
    |> case do
      {:ok, upstreams} -> {:ok, upstreams |> Enum.reverse() |> Enum.uniq()}
      {:error, _reason} = error -> error
    end
  end

  def prepare_allowed_upstreams(_entries), do: {:error, :dynamic_tool_bridge_allowed_upstreams_invalid}

  defp validate_base_url(base_url, opts) when is_binary(base_url) and is_list(opts) do
    with {:ok, normalized_base_url} <- normalize_base_url(base_url),
         :ok <- validate_allowed_upstream(normalized_base_url, opts),
         :ok <- validate_upstream_addresses(normalized_base_url, opts) do
      {:ok, normalized_base_url}
    end
  end

  defp normalize_base_url(base_url) when is_binary(base_url) do
    uri =
      base_url
      |> String.trim()
      |> String.trim_trailing("/")
      |> URI.parse()

    scheme = normalize_url_part(uri.scheme)
    host = normalize_url_part(uri.host)
    path = normalize_upstream_path(uri.path)

    cond do
      scheme not in ["http", "https"] ->
        {:error, :dynamic_tool_bridge_upstream_base_url_invalid}

      not is_binary(host) or host == "" ->
        {:error, :dynamic_tool_bridge_upstream_base_url_invalid}

      is_binary(uri.userinfo) or is_binary(uri.query) or is_binary(uri.fragment) ->
        {:error, :dynamic_tool_bridge_upstream_base_url_invalid}

      path != @base_path ->
        {:error, :dynamic_tool_bridge_upstream_base_url_invalid}

      true ->
        {:ok,
         %URI{uri | scheme: scheme, host: host, path: path, port: normalize_default_port(scheme, uri.port)}
         |> URI.to_string()}
    end
  end

  defp normalize_base_url(_base_url), do: {:error, :dynamic_tool_bridge_upstream_base_url_invalid}

  defp normalize_url_part(value) when is_binary(value), do: String.downcase(value)
  defp normalize_url_part(_value), do: nil

  defp normalize_upstream_path(nil), do: ""
  defp normalize_upstream_path(path) when is_binary(path), do: String.trim_trailing(path, "/")

  defp normalize_default_port("http", 80), do: nil
  defp normalize_default_port("https", 443), do: nil
  defp normalize_default_port(_scheme, port), do: port

  defp validate_allowed_upstream(base_url, opts) when is_binary(base_url) and is_list(opts) do
    with {:ok, allowed_upstreams} <- prepare_allowed_upstreams(Keyword.get(opts, :allowed_dynamic_tool_bridge_upstreams, [])) do
      cond do
        allowed_upstreams == [] ->
          {:error, :dynamic_tool_bridge_upstream_allowlist_missing}

        base_url in allowed_upstreams ->
          :ok

        true ->
          {:error, {:dynamic_tool_bridge_upstream_not_allowlisted, base_url}}
      end
    end
  end

  defp validate_upstream_addresses(base_url, opts) when is_binary(base_url) and is_list(opts) do
    host = base_url |> URI.parse() |> Map.fetch!(:host)
    allow_private? = Keyword.get(opts, :allow_private_dynamic_tool_bridge_upstreams?, false)

    with {:ok, addresses} <- resolve_host_addresses(host) do
      case Enum.find(addresses, &(not upstream_address_allowed?(&1, allow_private?))) do
        nil -> :ok
        address -> {:error, {:dynamic_tool_bridge_upstream_address_blocked, host, address, address_class(address)}}
      end
    end
  end

  defp resolve_host_addresses(host) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} ->
        {:ok, [address]}

      {:error, _reason} ->
        resolve_dns_addresses(host)
    end
  end

  defp resolve_dns_addresses(host) when is_binary(host) do
    {addresses, errors} =
      [:inet, :inet6]
      |> Enum.reduce({[], []}, fn family, {addresses, errors} ->
        case :inet.getaddrs(String.to_charlist(host), family) do
          {:ok, resolved} -> {addresses ++ resolved, errors}
          {:error, reason} -> {addresses, [{family, reason} | errors]}
        end
      end)

    case Enum.uniq(addresses) do
      [] -> {:error, {:dynamic_tool_bridge_upstream_address_unresolved, host, Enum.reverse(errors)}}
      resolved -> {:ok, resolved}
    end
  end

  defp upstream_address_allowed?(address, allow_private?) do
    case address_class(address) do
      :public -> true
      class when class in [:unspecified, :multicast, :reserved] -> false
      _private_class -> allow_private?
    end
  end

  defp address_class({0, 0, 0, 0}), do: :unspecified
  defp address_class({0, _b, _c, _d}), do: :reserved
  defp address_class({10, _b, _c, _d}), do: :private
  defp address_class({100, b, _c, _d}) when b in 64..127, do: :private
  defp address_class({127, _b, _c, _d}), do: :loopback
  defp address_class({169, 254, _c, _d}), do: :link_local
  defp address_class({172, b, _c, _d}) when b in 16..31, do: :private
  defp address_class({192, 168, _c, _d}), do: :private
  defp address_class({192, 0, 0, _d}), do: :reserved
  defp address_class({192, 0, 2, _d}), do: :reserved
  defp address_class({198, b, _c, _d}) when b in 18..19, do: :reserved
  defp address_class({198, 51, 100, _d}), do: :reserved
  defp address_class({203, 0, 113, _d}), do: :reserved
  defp address_class({a, _b, _c, _d}) when a in 224..239, do: :multicast
  defp address_class({a, _b, _c, _d}) when a >= 240, do: :reserved
  defp address_class({_a, _b, _c, _d}), do: :public
  defp address_class({0, 0, 0, 0, 0, 0, 0, 0}), do: :unspecified
  defp address_class({0, 0, 0, 0, 0, 0, 0, 1}), do: :loopback
  defp address_class({0, 0, 0, 0, 0, 65_535, high, low}), do: address_class(ipv4_from_words(high, low))
  defp address_class({0, 0, 0, 0, 0, 0, high, low}), do: address_class(ipv4_from_words(high, low))
  defp address_class({0x2001, 0x0DB8, _c, _d, _e, _f, _g, _h}), do: :reserved
  defp address_class({first, _b, _c, _d, _e, _f, _g, _h}) when first in 0xFC00..0xFDFF, do: :private
  defp address_class({first, _b, _c, _d, _e, _f, _g, _h}) when first in 0xFE80..0xFEBF, do: :link_local
  defp address_class({first, _b, _c, _d, _e, _f, _g, _h}) when first in 0xFF00..0xFFFF, do: :multicast
  defp address_class({_a, _b, _c, _d, _e, _f, _g, _h}), do: :public

  defp ipv4_from_words(high, low) when is_integer(high) and is_integer(low) do
    {div(high, 256), rem(high, 256), div(low, 256), rem(low, 256)}
  end
end
