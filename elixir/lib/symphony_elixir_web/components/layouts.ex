defmodule SymphonyElixirWeb.Layouts do
  @moduledoc """
  Shared layouts for the observability dashboard.
  """

  use Phoenix.Component

  alias SymphonyElixirWeb.BrowserPaths

  @spec root(map()) :: Phoenix.LiveView.Rendered.t()
  def root(assigns) do
    assigns =
      assigns
      |> assign(:csrf_token, Plug.CSRFProtection.get_csrf_token())
      |> assign(:live_socket_path, BrowserPaths.live_socket_path())

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={@csrf_token} />
        <title>Maestro Observability</title>
        <script defer src={BrowserPaths.phoenix_html_js_path()}></script>
        <script defer src={BrowserPaths.phoenix_js_path()}></script>
        <script defer src={BrowserPaths.phoenix_live_view_js_path()}></script>
        <script>
          window.addEventListener("DOMContentLoaded", function () {
            var csrfToken = document
              .querySelector("meta[name='csrf-token']")
              ?.getAttribute("content");

            if (!window.Phoenix || !window.LiveView) return;

            var liveSocket = new window.LiveView.LiveSocket(
              "{@live_socket_path}",
              window.Phoenix.Socket,
              {
              params: {_csrf_token: csrfToken}
              }
            );

            liveSocket.connect();
            window.liveSocket = liveSocket;
          });
        </script>
        <link rel="stylesheet" href={BrowserPaths.dashboard_css_path()} />
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  @spec app(map()) :: Phoenix.LiveView.Rendered.t()
  def app(assigns) do
    ~H"""
    <main class="app-shell">
      {@inner_content}
      <footer class="app-footer" aria-label="Legal">
        <a href={BrowserPaths.source_path()}>Source</a>
      </footer>
    </main>
    """
  end
end
