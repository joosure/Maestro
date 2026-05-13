defmodule SymphonyWorkerDaemon.Config.WorkerIdentity do
  @moduledoc false

  alias SymphonyWorkerDaemon.Config.Options

  @spec resolve(keyword(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def resolve(opts, deps) when is_list(opts) and is_map(deps) do
    default_worker_id =
      case deps.hostname.() do
        {:ok, value} -> value
        {:error, _reason} -> "worker-local"
      end

    Options.required_string(opts, :worker_id, default_worker_id, "worker id")
  end
end
