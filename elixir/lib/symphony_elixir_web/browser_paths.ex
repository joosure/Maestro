defmodule SymphonyElixirWeb.BrowserPaths do
  @moduledoc false

  @dashboard_css_path "/dashboard.css"
  @phoenix_html_js_path "/vendor/phoenix_html/phoenix_html.js"
  @phoenix_js_path "/vendor/phoenix/phoenix.js"
  @phoenix_live_view_js_path "/vendor/phoenix_live_view/phoenix_live_view.js"
  @live_socket_path "/live"
  @source_path "/source"
  @issue_route_path "/issues/:issue_identifier"

  @spec dashboard_css_path() :: String.t()
  def dashboard_css_path, do: @dashboard_css_path

  @spec phoenix_html_js_path() :: String.t()
  def phoenix_html_js_path, do: @phoenix_html_js_path

  @spec phoenix_js_path() :: String.t()
  def phoenix_js_path, do: @phoenix_js_path

  @spec phoenix_live_view_js_path() :: String.t()
  def phoenix_live_view_js_path, do: @phoenix_live_view_js_path

  @spec live_socket_path() :: String.t()
  def live_socket_path, do: @live_socket_path

  @spec source_path() :: String.t()
  def source_path, do: @source_path

  @spec issue_route_path() :: String.t()
  def issue_route_path, do: @issue_route_path

  @spec issue_path(String.t()) :: String.t()
  def issue_path(issue_identifier) when is_binary(issue_identifier) do
    "/issues/" <> URI.encode(issue_identifier, &URI.char_unreserved?/1)
  end
end
