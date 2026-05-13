defmodule SymphonyElixir.RepoProvider.CommandEvaluator do
  @moduledoc false

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.RepoProvider.Command
  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Invocation
  alias SymphonyElixir.RepoProvider.Output
  alias SymphonyElixir.RepoProvider.RuntimeConfig

  @repo_provider_runtime "symphony"

  @type deps :: %{
          required(:env) => (-> %{optional(String.t()) => String.t()} | [{String.t(), String.t()}]),
          required(:command_opts) => (-> keyword()),
          optional(:monotonic_time_ms) => (-> integer()),
          optional(:emit_event) => (atom(), atom(), map() -> map())
        }

  @spec evaluate([String.t()], deps()) :: {String.t(), String.t(), non_neg_integer()}
  def evaluate(argv, deps) when is_list(argv) and is_map(deps) do
    env_map = normalize_env(deps.env.())
    repo_config = RuntimeConfig.from_env(env_map)
    started_at_ms = monotonic_time_ms(deps)
    command_opts = command_opts(deps)

    case Invocation.parse(argv) do
      {:ok, invocation} ->
        resolved_repo = RuntimeConfig.apply_provider_override(repo_config, invocation.provider_override)
        provider_kind = RuntimeConfig.current_kind(resolved_repo)
        command_name = command_name(invocation.command)

        emit_repo_provider_event(
          deps,
          :info,
          :repo_provider_command_started,
          command_name,
          provider_kind,
          0,
          nil,
          command_opts
        )

        rendered =
          case Command.run(invocation, resolved_repo, command_opts) do
            {:ok, result} -> Output.render_with_diagnostics(result)
            {:error, %Error{} = error} -> Output.render_error_with_diagnostics(error)
          end

        emit_repo_provider_event(
          deps,
          rendered_log_level(rendered),
          :repo_provider_command_finished,
          command_name,
          provider_kind,
          monotonic_time_ms(deps) - started_at_ms,
          rendered,
          command_opts
        )

        render_tuple(rendered)

      {:error, %Error{} = error} ->
        rendered = Output.render_error_with_diagnostics(error)

        emit_repo_provider_event(
          deps,
          rendered_log_level(rendered),
          :repo_provider_command_finished,
          infer_command_name(argv),
          infer_provider_kind(argv, env_map),
          monotonic_time_ms(deps) - started_at_ms,
          rendered,
          command_opts
        )

        render_tuple(rendered)
    end
  end

  @spec runtime_deps() :: deps()
  def runtime_deps do
    %{
      env: &System.get_env/0,
      command_opts: fn -> [] end,
      monotonic_time_ms: fn -> System.monotonic_time(:millisecond) end,
      emit_event: &ObservabilityLogger.emit/3
    }
  end

  defp command_opts(deps) do
    case Map.get(deps, :command_opts) do
      nil -> []
      fun when is_function(fun, 0) -> fun.()
    end
  end

  defp monotonic_time_ms(deps) do
    case Map.get(deps, :monotonic_time_ms) do
      nil -> System.monotonic_time(:millisecond)
      fun when is_function(fun, 0) -> fun.()
    end
  end

  defp normalize_env(env) when is_map(env), do: env
  defp normalize_env(env) when is_list(env), do: Map.new(env)

  defp emit_repo_provider_event(deps, level, event, command_name, provider_kind, duration_ms, rendered, command_opts)
       when is_atom(level) and is_atom(event) and is_list(command_opts) do
    fields =
      %{
        component: "repo_provider.cli",
        operation_name: command_name,
        provider_kind: provider_kind,
        repo_provider_runtime: @repo_provider_runtime,
        duration_ms: duration_ms,
        retry_count: Keyword.get(command_opts, :retry_count, 0)
      }
      |> maybe_put_summary(rendered, command_name, provider_kind)
      |> maybe_put_error_fields(rendered)

    emit_event(deps).(level, event, fields)
  end

  defp emit_event(deps) do
    case Map.get(deps, :emit_event) do
      nil -> &ObservabilityLogger.emit/3
      fun when is_function(fun, 3) -> fun
    end
  end

  defp maybe_put_summary(fields, nil, command_name, provider_kind) do
    Map.put(fields, :payload_summary, "command=#{command_name} provider=#{provider_kind} runtime=#{@repo_provider_runtime}")
  end

  defp maybe_put_summary(fields, rendered, command_name, provider_kind) do
    Map.put(
      fields,
      :result_summary,
      "command=#{command_name} provider=#{provider_kind} runtime=#{@repo_provider_runtime} exit_code=#{rendered_exit_code(rendered)}"
    )
  end

  defp maybe_put_error_fields(fields, nil), do: fields

  defp maybe_put_error_fields(fields, %{exit_code: exit_code, error: nil}) do
    Map.put(fields, :exit_code, exit_code)
  end

  defp maybe_put_error_fields(fields, %{exit_code: exit_code, error: %Error{} = error}) do
    fields
    |> Map.put(:exit_code, exit_code)
    |> Map.put(:error_code, error.code)
    |> Map.put(:error, error.message)
  end

  defp rendered_log_level(%{error: %Error{}}), do: :warning
  defp rendered_log_level(_rendered), do: :info

  defp rendered_exit_code(%{exit_code: exit_code}), do: exit_code

  defp render_tuple(%{stdout: stdout, stderr: stderr, exit_code: exit_code}) do
    {stdout, stderr, exit_code}
  end

  defp command_name(command) when is_atom(command) do
    command
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp infer_provider_kind(["--provider", provider | _rest], _env_map) when is_binary(provider), do: provider
  defp infer_provider_kind(_argv, env_map), do: Map.get(env_map, "SYMPHONY_REPO_PROVIDER_KIND", "github")

  defp infer_command_name(["--provider", _provider, command | _rest]) when is_binary(command), do: command
  defp infer_command_name([command | _rest]) when is_binary(command), do: command
  defp infer_command_name(_argv), do: "unknown"
end
