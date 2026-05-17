defmodule SymphonyWorkerDaemon.Auth.Defaults do
  @moduledoc """
  Default identity values for Worker Daemon authentication.
  """

  @default_owner "symphony"
  @admin_role "admin"
  @session_owner_role "session_owner"

  @spec default_owner() :: String.t()
  def default_owner, do: @default_owner

  @spec admin_role() :: String.t()
  def admin_role, do: @admin_role

  @spec session_owner_role() :: String.t()
  def session_owner_role, do: @session_owner_role

  @spec default_principal() :: %{owner: String.t(), roles: [String.t()]}
  def default_principal, do: %{owner: @default_owner, roles: [@admin_role]}
end
