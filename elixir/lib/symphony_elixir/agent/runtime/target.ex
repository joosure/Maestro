defmodule SymphonyElixir.Agent.Runtime.Target do
  @moduledoc false

  @type placement :: :local | :ssh | :worker_daemon | :unsupported

  @local_executor Module.concat(["SymphonyElixir", "Agent", "Runtime", "Executor", "Local"])
  @ssh_executor Module.concat(["SymphonyElixir", "Agent", "Runtime", "Executor", "SSH"])
  @worker_daemon_executor Module.concat(["SymphonyElixir", "Agent", "Runtime", "Executor", "WorkerDaemon"])

  @type t :: %__MODULE__{
          placement: placement(),
          worker_pool: String.t() | nil,
          worker_host: String.t() | nil,
          workspace_path: Path.t(),
          remote_workspace_path: Path.t() | nil,
          env: map(),
          executor: module() | nil,
          metadata: map()
        }

  defstruct placement: :local,
            worker_pool: nil,
            worker_host: nil,
            workspace_path: nil,
            remote_workspace_path: nil,
            env: %{},
            executor: @local_executor,
            metadata: %{}

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    worker_host = normalize_optional_string(value(attrs, :worker_host))
    placement = normalize_placement(value(attrs, :placement), worker_host)

    %__MODULE__{
      placement: placement,
      worker_pool: normalize_optional_string(value(attrs, :worker_pool)),
      worker_host: worker_host,
      workspace_path: normalize_required_path(value(attrs, :workspace_path) || value(attrs, :workspace)),
      remote_workspace_path: normalize_optional_string(value(attrs, :remote_workspace_path)),
      env: normalize_env(value(attrs, :env)),
      executor: normalize_executor(value(attrs, :executor), placement),
      metadata: normalize_metadata(value(attrs, :metadata))
    }
  end

  @spec remote?(t()) :: boolean()
  def remote?(%__MODULE__{placement: :ssh}), do: true
  def remote?(%__MODULE__{placement: :worker_daemon}), do: true
  def remote?(%__MODULE__{}), do: false

  @spec to_context(t()) :: map()
  def to_context(%__MODULE__{} = target) do
    %{
      agent_runtime_target: target,
      worker_placement: Atom.to_string(target.placement),
      worker_pool: target.worker_pool,
      worker_host: target.worker_host,
      workspace_path: target.workspace_path,
      remote_workspace_path: target.remote_workspace_path,
      runtime_env: target.env
    }
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp normalize_placement(:local, _worker_host), do: :local
  defp normalize_placement("local", _worker_host), do: :local
  defp normalize_placement(:ssh, _worker_host), do: :ssh
  defp normalize_placement("ssh", _worker_host), do: :ssh
  defp normalize_placement(:worker_daemon, _worker_host), do: :worker_daemon
  defp normalize_placement("worker_daemon", _worker_host), do: :worker_daemon
  defp normalize_placement(nil, worker_host) when is_binary(worker_host), do: :ssh
  defp normalize_placement(nil, _worker_host), do: :local
  defp normalize_placement(_placement, _worker_host), do: :unsupported

  defp normalize_executor(nil, :worker_daemon), do: @worker_daemon_executor
  defp normalize_executor(nil, :ssh), do: @ssh_executor
  defp normalize_executor(nil, :local), do: @local_executor
  defp normalize_executor(executor, _placement) when is_atom(executor), do: executor
  defp normalize_executor(_executor, :worker_daemon), do: @worker_daemon_executor
  defp normalize_executor(_executor, :ssh), do: @ssh_executor
  defp normalize_executor(_executor, :local), do: @local_executor
  defp normalize_executor(_executor, :unsupported), do: nil

  defp normalize_required_path(value) when is_binary(value), do: Path.expand(value)
  defp normalize_required_path(value), do: to_string(value || "")

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  defp normalize_optional_string(_value), do: nil

  defp normalize_env(env) when is_map(env), do: env
  defp normalize_env(_env), do: %{}

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(_metadata), do: %{}
end
