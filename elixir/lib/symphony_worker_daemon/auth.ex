defmodule SymphonyWorkerDaemon.Auth do
  @moduledoc false

  alias SymphonyWorkerDaemon.Auth.{AccessPolicy, Clients, Defaults, Token, Values}

  @admin_role Defaults.admin_role()

  @type principal :: %{
          required(:owner) => String.t(),
          required(:roles) => [String.t()],
          optional(:tenant_id) => String.t(),
          optional(:auth_mode) => String.t()
        }

  @spec authenticate([String.t()], keyword()) :: {:ok, principal()} | {:error, :auth_failed}
  def authenticate(authorization_headers, opts) when is_list(authorization_headers) and is_list(opts) do
    case Token.bearer(authorization_headers) do
      nil -> authenticate_without_token(opts)
      token -> authenticate_token(token, opts)
    end
  end

  @spec authorize_create(principal(), map()) :: :ok | {:error, :session_forbidden}
  defdelegate authorize_create(principal, request), to: AccessPolicy

  @spec authorize_session(principal(), map()) :: :ok | {:error, :session_forbidden}
  defdelegate authorize_session(principal, session_summary), to: AccessPolicy

  @spec authorize_filters(principal(), map()) :: {:ok, map()} | {:error, :session_forbidden}
  defdelegate authorize_filters(principal, filters), to: AccessPolicy

  @spec principal_summary(principal()) :: map()
  defdelegate principal_summary(principal), to: AccessPolicy

  defp authenticate_without_token(opts) do
    cond do
      auth_required?(opts) ->
        {:error, :auth_failed}

      true ->
        {:ok,
         %{
           owner: default_owner(opts),
           roles: [@admin_role],
           auth_mode: "unauthenticated"
         }
         |> Values.maybe_put_tenant(default_tenant_id(opts))}
    end
  end

  defp authenticate_token(token, opts) when is_binary(token) do
    opts
    |> clients()
    |> Enum.find(&Token.match?(token, Map.fetch!(&1, :token)))
    |> case do
      nil -> {:error, :auth_failed}
      client -> {:ok, Map.delete(client, :token)}
    end
  end

  defp auth_required?(opts) do
    case Keyword.get(opts, :api_clients) do
      clients when is_list(clients) and clients != [] -> true
      _clients -> token_configured?(opts) or not Keyword.get(opts, :allow_unauthenticated?, false)
    end
  end

  defp token_configured?(opts) do
    opts
    |> Keyword.get(:token)
    |> Values.normalize_optional_string()
    |> is_binary()
  end

  defp clients(opts) do
    Clients.build(opts, default_owner(opts), @admin_role, default_tenant_id(opts))
  end

  defp default_owner(opts) do
    owner =
      opts
      |> Keyword.get(:owner, Defaults.default_owner())
      |> Values.normalize_optional_string()

    owner || Defaults.default_owner()
  end

  defp default_tenant_id(opts), do: opts |> Keyword.get(:tenant_id) |> Values.normalize_optional_string()
end
