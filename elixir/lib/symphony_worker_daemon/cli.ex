defmodule SymphonyWorkerDaemon.CLI do
  @moduledoc false

  alias SymphonyWorkerDaemon.CLI.{Arguments, Output, ServerSpec}

  @supervisor_name SymphonyWorkerDaemon.CLI.Supervisor

  @type deps :: %{
          ensure_dependencies: (-> :ok | {:error, term()}),
          start_server: (keyword() -> {:ok, pid()} | {:error, term()}),
          dir?: (String.t() -> boolean()),
          canonicalize: (String.t() -> {:ok, String.t()} | {:error, term()}),
          getenv: (String.t() -> String.t() | nil),
          hostname: (-> {:ok, String.t()} | {:error, term()}),
          uuid: (-> String.t())
        }

  @spec main([String.t()]) :: no_return()
  def main(args) do
    case evaluate(args) do
      :ok ->
        wait_for_shutdown()

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  @spec evaluate([String.t()], deps()) :: :ok | {:error, String.t()}
  def evaluate(args, deps \\ runtime_deps()) when is_list(args) and is_map(deps) do
    with {:ok, opts} <- Arguments.parse(args),
         {:ok, server_opts} <- normalize_options(opts, deps),
         :ok <- deps.ensure_dependencies.(),
         {:ok, _pid} <- deps.start_server.(server_opts) do
      Output.started(server_opts)
      :ok
    else
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, "Failed to start Symphony worker daemon: #{inspect(reason)}"}
    end
  end

  @spec start_server(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_server(opts) when is_list(opts) do
    Supervisor.start_link(ServerSpec.children(opts), strategy: :one_for_one, name: Keyword.get(opts, :supervisor_name, @supervisor_name))
  end

  @spec runtime_deps() :: deps()
  def runtime_deps do
    %{
      ensure_dependencies: &ensure_dependencies/0,
      start_server: &start_server/1,
      dir?: &File.dir?/1,
      canonicalize: &SymphonyElixir.PathSafety.canonicalize/1,
      getenv: &System.get_env/1,
      hostname: &hostname/0,
      uuid: &Ecto.UUID.generate/0
    }
  end

  defp normalize_options(opts, deps) do
    with {:ok, config} <- SymphonyWorkerDaemon.Config.normalize_cli_options(opts, deps) do
      {:ok, SymphonyWorkerDaemon.Config.to_server_opts(config)}
    end
  end

  defp ensure_dependencies do
    with {:ok, _started} <- Application.ensure_all_started(:crypto),
         {:ok, _started} <- Application.ensure_all_started(:bandit),
         {:ok, _started} <- Application.ensure_all_started(:req) do
      :ok
    end
  end

  defp hostname do
    case :inet.gethostname() do
      {:ok, hostname} -> {:ok, List.to_string(hostname)}
    end
  end

  @spec wait_for_shutdown() :: no_return()
  defp wait_for_shutdown do
    case Process.whereis(@supervisor_name) do
      nil ->
        IO.puts(:stderr, "Symphony worker daemon supervisor is not running")
        System.halt(1)

      pid ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, reason} ->
            case reason do
              :normal -> System.halt(0)
              _reason -> System.halt(1)
            end
        end
    end
  end
end
