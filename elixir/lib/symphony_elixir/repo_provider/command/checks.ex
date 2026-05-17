defmodule SymphonyElixir.RepoProvider.Command.Checks do
  @moduledoc false

  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.RepoProvider.CheckRun
  alias SymphonyElixir.RepoProvider.Command.Options
  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Invocation
  alias SymphonyElixir.RepoProvider.Query
  alias SymphonyElixir.RepoProvider.Result

  @default_watch_poll_ms 10_000

  @spec run(map(), Invocation.t(), keyword(), String.t()) :: {:ok, Result.t()} | {:error, Error.t()}
  def run(repo_config, %Invocation{} = invocation, opts, query_label)
      when is_map(repo_config) and is_list(opts) and is_binary(query_label) do
    if invocation.watch? do
      run_watch(repo_config, invocation, opts, query_label, [])
    else
      with {:ok, check_runs} <- RepoProvider.pr_checks(repo_config, Options.pr_checks_opts(invocation, opts)) do
        result(check_runs, invocation, query_label)
      end
    end
  end

  defp result(check_runs, %Invocation{json?: true} = invocation, query_label) do
    {:ok,
     %Result{
       mode: :json,
       payload: check_runs,
       jq: invocation.jq,
       query_label: query_label,
       exit_code: exit_code(check_runs)
     }}
  end

  defp result(check_runs, _invocation, _query_label) do
    {:ok,
     %Result{
       mode: :text,
       payload: render_summary(check_runs),
       exit_code: exit_code(check_runs)
     }}
  end

  defp run_watch(repo_config, invocation, opts, query_label, acc) do
    with {:ok, check_runs} <- RepoProvider.pr_checks(repo_config, Options.pr_checks_opts(invocation, opts)),
         {:ok, output} <- render_iteration(check_runs, invocation, query_label) do
      updated_acc = [acc, output]
      {pending, failed} = pending_and_failed(check_runs)

      cond do
        failed ->
          {:ok, %Result{mode: :text, payload: IO.iodata_to_binary(updated_acc), exit_code: 1}}

        not pending ->
          {:ok, %Result{mode: :text, payload: IO.iodata_to_binary(updated_acc), exit_code: 0}}

        true ->
          sleep_fn = Keyword.get(opts, :sleep_fn, &Process.sleep/1)
          sleep_fn.(Keyword.get(opts, :watch_poll_ms, @default_watch_poll_ms))
          run_watch(repo_config, invocation, opts, query_label, updated_acc)
      end
    end
  end

  defp render_iteration(check_runs, %Invocation{json?: true, jq: jq}, query_label)
       when is_binary(jq) do
    Query.run(check_runs, jq, query_label)
  end

  defp render_iteration(check_runs, %Invocation{json?: true}, _query_label) do
    {:ok, Jason.encode!(check_runs) <> "\n"}
  end

  defp render_iteration(check_runs, _invocation, _query_label) do
    {:ok, render_summary(check_runs)}
  end

  defp render_summary([]), do: "no checks reported\n"

  defp render_summary(check_runs) do
    check_runs
    |> Enum.map(fn check ->
      name = CheckRun.name(check)
      status = CheckRun.display_status(check)
      conclusion = CheckRun.display_conclusion(check)
      summary = check["summary"] || check[:summary] || ""
      suffix = if summary == "", do: "", else: " (#{summary})"
      "#{name}: #{status}/#{conclusion}#{suffix}\n"
    end)
    |> IO.iodata_to_binary()
  end

  defp exit_code(check_runs) do
    case pending_and_failed(check_runs) do
      {false, false} -> 0
      _other -> 1
    end
  end

  defp pending_and_failed(check_runs) do
    Enum.reduce(check_runs, {false, false}, fn check, {pending, failed} ->
      conclusion = CheckRun.conclusion(check)

      cond do
        not CheckRun.completed?(check) ->
          {true, failed}

        CheckRun.successful_conclusion?(conclusion) ->
          {pending, failed}

        true ->
          {pending, true}
      end
    end)
  end
end
