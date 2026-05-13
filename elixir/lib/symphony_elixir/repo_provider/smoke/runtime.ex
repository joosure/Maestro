defmodule SymphonyElixir.RepoProvider.Smoke.Runtime do
  @moduledoc false

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.Platform.CommandEnv
  alias SymphonyElixir.RepoProvider.CommandEvaluator

  @spec runtime_deps() :: map()
  def runtime_deps do
    %{
      env: &System.get_env/0,
      command_opts: fn -> [] end,
      cli_evaluate: &CommandEvaluator.evaluate/2,
      monotonic_time_ms: fn -> System.monotonic_time(:millisecond) end,
      emit_event: &ObservabilityLogger.emit/3,
      system_cmd: &default_system_cmd/3,
      mk_temp_dir: &default_mk_temp_dir/1,
      write_file: &File.write/2,
      rm_rf: &File.rm_rf/1,
      sleep_ms: &Process.sleep/1
    }
  end

  @spec env_map(keyword(), map()) :: map()
  def env_map(opts, deps) do
    deps.env.()
    |> normalize_env()
    |> maybe_put_env("SYMPHONY_REPO_PROVIDER_REPOSITORY", Keyword.get(opts, :repo))
  end

  @spec cli_deps(map(), map()) :: map()
  def cli_deps(env_map, deps) do
    %{
      env: fn -> env_map end,
      command_opts: fn -> command_opts(deps) end,
      stdout: fn _output -> :ok end,
      stderr: fn _output -> :ok end,
      halt: fn status -> raise "repo-provider smoke unexpectedly halted with status #{status}" end
    }
  end

  defp command_opts(deps) do
    case Map.get(deps, :command_opts) do
      nil -> []
      fun when is_function(fun, 0) -> fun.()
    end
  end

  defp normalize_env(env) when is_map(env), do: env
  defp normalize_env(env) when is_list(env), do: Map.new(env)

  defp maybe_put_env(env_map, _key, nil), do: env_map
  defp maybe_put_env(env_map, _key, ""), do: env_map
  defp maybe_put_env(env_map, key, value) when is_binary(value), do: Map.put(env_map, key, value)

  defp default_system_cmd(command, argv, opts) do
    CommandEnv.system_cmd(command, argv, Keyword.merge([stderr_to_stdout: true], opts))
  end

  defp default_mk_temp_dir(prefix) when is_binary(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive, :monotonic])}")

    case File.mkdir_p(path) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
  end
end
