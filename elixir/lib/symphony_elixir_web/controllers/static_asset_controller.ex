defmodule SymphonyElixirWeb.StaticAssetController do
  @moduledoc """
  Serves the dashboard's embedded CSS and JavaScript assets.
  """

  use Phoenix.Controller, formats: []

  alias Plug.Conn
  alias SymphonyElixirWeb.BrowserPaths
  alias SymphonyElixirWeb.StaticAssets

  @spec dashboard_css(Conn.t(), map()) :: Conn.t()
  def dashboard_css(conn, _params), do: serve(conn, BrowserPaths.dashboard_css_path())

  @spec phoenix_html_js(Conn.t(), map()) :: Conn.t()
  def phoenix_html_js(conn, _params), do: serve(conn, BrowserPaths.phoenix_html_js_path())

  @spec phoenix_js(Conn.t(), map()) :: Conn.t()
  def phoenix_js(conn, _params), do: serve(conn, BrowserPaths.phoenix_js_path())

  @spec phoenix_live_view_js(Conn.t(), map()) :: Conn.t()
  def phoenix_live_view_js(conn, _params), do: serve(conn, BrowserPaths.phoenix_live_view_js_path())

  defp serve(conn, path) do
    case StaticAssets.fetch(path) do
      {:ok, content_type, body} ->
        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("cache-control", "public, max-age=31536000")
        |> send_resp(200, body)

      :error ->
        send_resp(conn, 404, "Not Found")
    end
  end
end
