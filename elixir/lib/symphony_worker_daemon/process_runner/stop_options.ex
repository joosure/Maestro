defmodule SymphonyWorkerDaemon.ProcessRunner.StopOptions do
  @moduledoc false

  @default_grace_ms 500
  @default_kill_wait_ms 500

  @spec build(keyword()) :: keyword()
  def build(opts) when is_list(opts) do
    [
      process_group?: Keyword.get(opts, :process_group?, true),
      grace_ms: Keyword.get(opts, :grace_ms, @default_grace_ms),
      kill_wait_ms: Keyword.get(opts, :kill_wait_ms, @default_kill_wait_ms),
      poll_ms: Keyword.get(opts, :poll_ms, 25)
    ]
  end
end
