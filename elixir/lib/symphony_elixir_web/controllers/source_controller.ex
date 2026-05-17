defmodule SymphonyElixirWeb.SourceController do
  @moduledoc """
  Source availability notice for AGPL network interaction.
  """

  use Phoenix.Controller, formats: [:html, :json]

  alias Plug.Conn
  alias SymphonyElixir.LegalSourceInfo
  alias SymphonyElixir.LegalSourceInfo.RuntimeEnv, as: LegalSourceRuntimeEnv
  alias SymphonyElixirWeb.BrowserPaths

  @spec show(Conn.t(), map()) :: Conn.t()
  def show(conn, _params) do
    notice = source_notice()

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html_document(notice))
  end

  @spec metadata(Conn.t(), map()) :: Conn.t()
  def metadata(conn, _params) do
    json(conn, source_notice())
  end

  defp source_notice, do: LegalSourceInfo.payload(notice_path: BrowserPaths.source_path())

  defp html_document(%{"source_url" => source_url, "source_revision" => source_revision}) do
    source_revision_env = LegalSourceRuntimeEnv.source_revision_envs() |> List.first()

    revision_markup =
      case source_revision do
        value when is_binary(value) and value != "" ->
          """
          <p class="legal-meta">
            Running source revision: <code>#{escape(value)}</code>
          </p>
          """

        _value ->
          """
          <p class="legal-meta">
            No deployment revision was configured. Operators should set <code>#{source_revision_env}</code> when serving a specific commit, tag, or release.
          </p>
          """
      end

    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Maestro Source Code</title>
        <link rel="stylesheet" href="#{BrowserPaths.dashboard_css_path()}" />
      </head>
      <body>
        <main class="app-shell legal-shell">
          <section class="legal-card">
            <p class="eyebrow">Source availability</p>
            <h1 class="legal-title">Maestro Source Code</h1>
            <p class="legal-copy">
              Maestro is licensed under the GNU Affero General Public License version 3 (AGPL-3.0-only).
              Users interacting with this network service can access the Corresponding Source for this deployment at:
            </p>
            <p class="legal-source-link">
              <a href="#{escape_attr(source_url)}" rel="noreferrer">#{escape(source_url)}</a>
            </p>
            #{revision_markup}
            <p class="legal-copy">
              Portions derived from OpenAI Symphony retain Apache-2.0 attribution and notice requirements.
              Review <code>NOTICE</code>, <code>LICENSE</code>, <code>LICENSES/Apache-2.0.txt</code>, <code>MODIFICATIONS.md</code>, <code>SOURCE.md</code>, and <code>THIRD_PARTY_LICENSES.md</code> in the source distribution.
            </p>
          </section>
        </main>
      </body>
    </html>
    """
  end

  defp escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp escape_attr(value), do: escape(value)
end
