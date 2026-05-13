defmodule SymphonyWorkerDaemon.Application.Children do
  @moduledoc false

  alias SymphonyWorkerDaemon.{CapacityManager, OrphanSweeper, RateLimiter}
  alias SymphonyWorkerDaemon.Session

  @default_max_sessions 1

  @spec build(keyword()) :: [{module(), keyword()}]
  def build(opts) when is_list(opts) do
    registry = Keyword.get(opts, :registry, SymphonyWorkerDaemon.SessionRegistry)
    capacity_manager = Keyword.get(opts, :capacity_manager, CapacityManager)
    rate_limiter = Keyword.get(opts, :rate_limiter, RateLimiter)
    session_ledger = Keyword.get(opts, :session_ledger, Session.Ledger)
    session_supervisor = Keyword.get(opts, :session_supervisor, Session.Supervisor)

    [
      {Session.Ledger, name: session_ledger, path: Keyword.get(opts, :session_ledger_path)},
      {OrphanSweeper,
       session_ledger: session_ledger,
       workspace_roots: Keyword.get(opts, :workspace_roots, []),
       enabled?: Keyword.get(opts, :orphan_sweep?, true),
       grace_ms: Keyword.get(opts, :orphan_sweep_grace_ms),
       kill_wait_ms: Keyword.get(opts, :orphan_sweep_kill_wait_ms),
       poll_ms: Keyword.get(opts, :orphan_sweep_poll_ms)}
    ] ++
      rate_limiter_children(rate_limiter, opts) ++
      [
        {Registry, keys: :unique, name: registry},
        {CapacityManager, name: capacity_manager, max_sessions: Keyword.get(opts, :max_sessions, @default_max_sessions), max_sessions_per_tenant: Keyword.get(opts, :max_sessions_per_tenant)},
        {Session.Supervisor, name: session_supervisor, session_ledger: session_ledger}
      ]
  end

  defp rate_limiter_children(nil, _opts), do: []

  defp rate_limiter_children(rate_limiter, opts) do
    [{RateLimiter, name: rate_limiter, max_buckets: Keyword.get(opts, :rate_limit_max_buckets)}]
  end
end
