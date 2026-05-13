defmodule SymphonyWorkerDaemon.Auth.AccessPolicy do
  @moduledoc false

  alias SymphonyWorkerDaemon.Auth.Values

  @admin_role "admin"

  @spec authorize_create(map(), map()) :: :ok | {:error, :session_forbidden}
  def authorize_create(principal, request) when is_map(principal) and is_map(request) do
    request
    |> caller_identity()
    |> authorize_identity(principal)
  end

  @spec authorize_session(map(), map()) :: :ok | {:error, :session_forbidden}
  def authorize_session(principal, session_summary) when is_map(principal) and is_map(session_summary) do
    session_summary
    |> session_identity()
    |> authorize_identity(principal)
  end

  @spec authorize_filters(map(), map()) :: {:ok, map()} | {:error, :session_forbidden}
  def authorize_filters(principal, filters) when is_map(principal) and is_map(filters) do
    if admin?(principal) do
      {:ok, filters}
    else
      authorize_owner_filter(principal, filters)
    end
  end

  @spec principal_summary(map()) :: map()
  def principal_summary(principal) when is_map(principal) do
    %{
      owner: Map.get(principal, :owner),
      tenant_id: Map.get(principal, :tenant_id),
      roles: Map.get(principal, :roles, [])
    }
    |> Values.compact_map()
  end

  defp authorize_identity(identity, principal) do
    cond do
      admin?(principal) ->
        :ok

      Map.get(identity, :owner) != Map.get(principal, :owner) ->
        {:error, :session_forbidden}

      tenant_mismatch?(principal, identity) ->
        {:error, :session_forbidden}

      true ->
        :ok
    end
  end

  defp authorize_owner_filter(principal, filters) do
    requested_owner = filters |> Map.get("owner") |> Values.normalize_optional_string()
    requested_tenant_id = filters |> Map.get("tenant_id") |> Values.normalize_optional_string()
    principal_owner = Map.fetch!(principal, :owner)
    principal_tenant_id = Map.get(principal, :tenant_id)

    cond do
      requested_owner && requested_owner != principal_owner ->
        {:error, :session_forbidden}

      is_binary(principal_tenant_id) && requested_tenant_id && requested_tenant_id != principal_tenant_id ->
        {:error, :session_forbidden}

      true ->
        {:ok,
         filters
         |> Map.put("owner", principal_owner)
         |> Values.maybe_put_string("tenant_id", principal_tenant_id)}
    end
  end

  defp tenant_mismatch?(%{tenant_id: tenant_id}, identity) when is_binary(tenant_id) do
    Map.get(identity, :tenant_id) != tenant_id
  end

  defp tenant_mismatch?(_principal, _identity), do: false

  defp admin?(principal) when is_map(principal), do: @admin_role in Map.get(principal, :roles, [])

  defp caller_identity(%{"caller" => caller}) when is_map(caller) do
    %{
      owner: caller |> Map.get("owner") |> Values.normalize_optional_string(),
      tenant_id: caller |> Map.get("tenant_id") |> Values.normalize_optional_string()
    }
    |> Values.compact_map()
  end

  defp caller_identity(_request), do: %{}

  defp session_identity(summary) when is_map(summary) do
    %{
      owner: summary |> Values.known_value("owner", :owner) |> Values.normalize_optional_string(),
      tenant_id: summary |> Values.known_value("tenant_id", :tenant_id) |> Values.normalize_optional_string()
    }
    |> Values.compact_map()
  end
end
