defmodule SymphonyElixirWeb.HealthController do
  @moduledoc """
  Lightweight health endpoints for container and orchestrator probes.
  """

  use Phoenix.Controller, formats: [:json]

  @spec health(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def health(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
