defmodule SymphonyElixirWeb.Router do
  @moduledoc """
  Router for Symphony's observability dashboard and API.
  """

  use Phoenix.Router
  import Phoenix.LiveView.Router

  alias SymphonyElixir.Platform.DynamicToolBridgeContract, as: BridgeContract
  alias SymphonyElixirWeb.BrowserPaths
  alias SymphonyElixirWeb.Observability.Paths

  @dynamic_tool_execute_path BridgeContract.execute_path()
  @dashboard_css_path BrowserPaths.dashboard_css_path()
  @phoenix_html_js_path BrowserPaths.phoenix_html_js_path()
  @phoenix_js_path BrowserPaths.phoenix_js_path()
  @phoenix_live_view_js_path BrowserPaths.phoenix_live_view_js_path()
  @source_browser_path BrowserPaths.source_path()
  @issue_browser_route_path BrowserPaths.issue_route_path()
  @api_source_path Paths.source_path()
  @api_state_path Paths.state_path()
  @api_refresh_path Paths.refresh_path()
  @api_issue_route_path Paths.issue_route_path()

  pipeline :browser do
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {SymphonyElixirWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", SymphonyElixirWeb do
    get("/healthz", HealthController, :health)
    get(@dashboard_css_path, StaticAssetController, :dashboard_css)
    get(@phoenix_html_js_path, StaticAssetController, :phoenix_html_js)
    get(@phoenix_js_path, StaticAssetController, :phoenix_js)
    get(@phoenix_live_view_js_path, StaticAssetController, :phoenix_live_view_js)
  end

  scope "/", SymphonyElixirWeb do
    pipe_through(:browser)

    get(@source_browser_path, SourceController, :show)
    live(@issue_browser_route_path, DashboardLive, :issue)
    live("/", DashboardLive, :index)
  end

  scope "/", SymphonyElixirWeb do
    get(@api_source_path, SourceController, :metadata)
    get(@api_state_path, ObservabilityApiController, :state)
    post(@dynamic_tool_execute_path, DynamicToolController, :execute)
    match(:*, @dynamic_tool_execute_path, ObservabilityApiController, :method_not_allowed)

    match(:*, "/", ObservabilityApiController, :method_not_allowed)
    match(:*, @api_source_path, ObservabilityApiController, :method_not_allowed)
    match(:*, @api_state_path, ObservabilityApiController, :method_not_allowed)
    post(@api_refresh_path, ObservabilityApiController, :refresh)
    match(:*, @api_refresh_path, ObservabilityApiController, :method_not_allowed)
    get(@api_issue_route_path, ObservabilityApiController, :issue)
    match(:*, @api_issue_route_path, ObservabilityApiController, :method_not_allowed)
    match(:*, "/*path", ObservabilityApiController, :not_found)
  end
end
