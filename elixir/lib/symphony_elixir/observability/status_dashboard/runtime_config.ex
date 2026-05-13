defmodule SymphonyElixir.Observability.StatusDashboard.RuntimeConfig do
  @moduledoc false

  alias SymphonyElixir.Config
  alias SymphonyElixir.Observability.StatusDashboard.Terminal

  @type values :: %{
          refresh_ms: pos_integer(),
          enabled: boolean(),
          render_interval_ms: pos_integer(),
          refresh_ms_override: pos_integer() | nil,
          enabled_override: boolean() | nil,
          render_interval_ms_override: pos_integer() | nil,
          render_fun: (String.t() -> term())
        }

  @spec initial_values(keyword()) :: values()
  def initial_values(opts) do
    refresh_ms_override = keyword_override(opts, :refresh_ms)
    enabled_override = keyword_override(opts, :enabled)
    render_interval_ms_override = keyword_override(opts, :render_interval_ms)
    observability = Config.settings!().observability

    %{
      refresh_ms: refresh_ms_override || observability.refresh_ms,
      enabled: resolve_override(enabled_override, observability.dashboard_enabled and dashboard_enabled?()),
      render_interval_ms: render_interval_ms_override || observability.render_interval_ms,
      refresh_ms_override: refresh_ms_override,
      enabled_override: enabled_override,
      render_interval_ms_override: render_interval_ms_override,
      render_fun: Keyword.get(opts, :render_fun, &Terminal.render_to_terminal/1)
    }
  end

  @spec refresh(map()) :: map()
  def refresh(state) do
    observability = Config.settings!().observability

    %{
      state
      | enabled: resolve_override(state.enabled_override, observability.dashboard_enabled and dashboard_enabled?()),
        refresh_ms: state.refresh_ms_override || observability.refresh_ms,
        render_interval_ms: state.render_interval_ms_override || observability.render_interval_ms
    }
  end

  defp dashboard_enabled?, do: Application.get_env(:symphony_elixir, :env, :prod) != :test

  defp keyword_override(opts, key) do
    if Keyword.has_key?(opts, key), do: Keyword.fetch!(opts, key), else: nil
  end

  defp resolve_override(nil, default), do: default
  defp resolve_override(override, _default), do: override
end
