defmodule SymphonyWorkerDaemon.Auth.Clients do
  @moduledoc false

  alias SymphonyWorkerDaemon.Auth.{Defaults, Values}

  @spec build(keyword(), String.t(), String.t(), String.t() | nil) :: [map()]
  def build(opts, default_owner, admin_role, default_tenant_id) when is_list(opts) and is_binary(default_owner) and is_binary(admin_role) do
    case Keyword.get(opts, :api_clients) do
      clients when is_list(clients) and clients != [] ->
        Enum.flat_map(clients, &normalize_client(&1, admin_role))

      _clients ->
        default_client(opts, default_owner, admin_role, default_tenant_id)
    end
  end

  @spec normalize_roles(term()) :: [String.t()]
  def normalize_roles(values) do
    values
    |> List.wrap()
    |> Enum.map(&Values.normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
    |> maybe_default_roles()
  end

  defp default_client(opts, default_owner, _admin_role, default_tenant_id) do
    case opts |> Keyword.get(:token) |> Values.normalize_optional_string() do
      nil ->
        []

      token ->
        [
          %{
            token: token,
            owner: default_owner,
            roles: normalize_roles(Keyword.get(opts, :roles, [])),
            auth_mode: "bearer"
          }
          |> Values.maybe_put_tenant(default_tenant_id)
        ]
    end
  end

  defp normalize_client(client, admin_role) when is_map(client) or is_list(client) do
    with token when is_binary(token) <- client |> Values.value(:token) |> Values.normalize_optional_string(),
         owner when is_binary(owner) <- client |> Values.value(:owner) |> Values.normalize_optional_string() do
      [
        %{
          token: token,
          owner: owner,
          roles: client |> roles_value(admin_role) |> normalize_roles(),
          auth_mode: "bearer"
        }
        |> Values.maybe_put_tenant(client |> Values.value(:tenant_id) |> Values.normalize_optional_string())
      ]
    else
      _invalid -> []
    end
  end

  defp normalize_client(_client, _admin_role), do: []

  defp roles_value(client, admin_role) do
    roles = Values.value(client, :roles)

    if Values.truthy?(Values.value(client, :admin?)) or Values.truthy?(Values.value(client, :admin)) do
      [admin_role | List.wrap(roles)]
    else
      roles || []
    end
  end

  defp maybe_default_roles([]), do: [Defaults.session_owner_role()]
  defp maybe_default_roles(roles), do: Enum.uniq(roles)
end
