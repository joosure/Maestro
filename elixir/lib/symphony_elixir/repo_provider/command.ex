defmodule SymphonyElixir.RepoProvider.Command do
  @moduledoc false

  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Invocation
  alias SymphonyElixir.RepoProvider.LandWatch
  alias SymphonyElixir.RepoProvider.Query
  alias SymphonyElixir.RepoProvider.Result

  @default_watch_poll_ms 10_000

  @spec run(Invocation.t(), map(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def run(invocation, repo_config, opts \\ [])

  def run(%Invocation{command: :current_kind}, repo_config, _opts) do
    {:ok,
     %Result{
       mode: :text,
       payload: RepoProvider.current_kind(repo_config)
     }}
  end

  def run(%Invocation{command: :auth_status}, repo_config, opts) do
    with {:ok, payload} <- RepoProvider.auth_status(repo_config, opts) do
      {:ok, %Result{mode: :text, payload: payload}}
    end
  end

  def run(%Invocation{command: :pr_view} = invocation, repo_config, opts) do
    with {:ok, payload} <- RepoProvider.pr_view(repo_config, invocation_opts(invocation, [:number], opts)) do
      {:ok,
       %Result{
         mode: :json,
         payload: payload,
         json_fields: invocation.json_fields,
         jq: invocation.jq,
         query_label: query_label(repo_config)
       }}
    end
  end

  def run(%Invocation{command: :pr_create} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_create(
             repo_config,
             invocation_opts(invocation, [:title, :body, :base, :head], opts)
           ) do
      {:ok, %Result{mode: :text, payload: payload}}
    end
  end

  def run(%Invocation{command: :pr_edit} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_edit(
             repo_config,
             invocation_opts(invocation, [:number, :title, :body, :base], opts)
           ) do
      {:ok, %Result{mode: :text, payload: payload}}
    end
  end

  def run(%Invocation{command: :pr_add_label} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_add_label(
             repo_config,
             invocation_opts(invocation, [:label, :number], opts)
           ) do
      {:ok, %Result{mode: :text, payload: payload}}
    end
  end

  def run(%Invocation{command: :pr_issue_comments} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_issue_comments(
             repo_config,
             invocation_opts(invocation, [:number], opts)
           ) do
      {:ok,
       %Result{
         mode: :json,
         payload: payload,
         json_fields: invocation.json_fields,
         jq: invocation.jq,
         query_label: query_label(repo_config)
       }}
    end
  end

  def run(%Invocation{command: :pr_add_issue_comment} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_add_issue_comment(
             repo_config,
             invocation_opts(invocation, [:body, :number], opts)
           ) do
      {:ok, %Result{mode: :json, payload: payload, query_label: query_label(repo_config)}}
    end
  end

  def run(%Invocation{command: :pr_reviews} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_reviews(
             repo_config,
             invocation_opts(invocation, [:number], opts)
           ) do
      {:ok,
       %Result{
         mode: :json,
         payload: payload,
         json_fields: invocation.json_fields,
         jq: invocation.jq,
         query_label: query_label(repo_config)
       }}
    end
  end

  def run(%Invocation{command: :pr_review_comments} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_review_comments(
             repo_config,
             invocation_opts(invocation, [:number], opts)
           ) do
      {:ok,
       %Result{
         mode: :json,
         payload: payload,
         json_fields: invocation.json_fields,
         jq: invocation.jq,
         query_label: query_label(repo_config)
       }}
    end
  end

  def run(%Invocation{command: :pr_reply_review_comment} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_reply_review_comment(
             repo_config,
             invocation_opts(invocation, [:comment_id, :body, :number], opts)
           ) do
      {:ok, %Result{mode: :json, payload: payload, query_label: query_label(repo_config)}}
    end
  end

  def run(%Invocation{command: :pr_close} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_close(
             repo_config,
             invocation_opts(invocation, [:number, :comment], opts)
           ) do
      {:ok, %Result{mode: :text, payload: payload}}
    end
  end

  def run(%Invocation{command: :pr_merge} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_merge(
             repo_config,
             invocation_opts(invocation, [:number, :merge_style, :subject, :body], opts)
           ) do
      {:ok, %Result{mode: :text, payload: payload}}
    end
  end

  def run(%Invocation{command: :pr_land_watch} = invocation, repo_config, opts) do
    watch_opts =
      opts
      |> maybe_put(:number, invocation.number)
      |> maybe_put(:poll_ms, invocation.poll_ms)
      |> maybe_put(:checks_appear_timeout_ms, invocation.checks_appear_timeout_ms)

    with {:ok, output, exit_code} <- LandWatch.watch(repo_config, watch_opts) do
      {:ok, %Result{mode: :text, payload: output, exit_code: exit_code}}
    end
  end

  def run(%Invocation{command: :pr_checks} = invocation, repo_config, opts) do
    if invocation.watch? do
      run_pr_checks_watch(repo_config, invocation, opts, [])
    else
      with {:ok, check_runs} <- RepoProvider.pr_checks(repo_config, pr_checks_opts(invocation, opts)) do
        pr_checks_result(check_runs, invocation, repo_config)
      end
    end
  end

  def run(%Invocation{command: :api} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.api(
             repo_config,
             api_opts(invocation, opts)
           ) do
      {:ok,
       %Result{
         mode: :json,
         payload: payload,
         jq: invocation.jq,
         query_label: query_label(repo_config)
       }}
    end
  end

  def run(%Invocation{command: :run_list} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.run_list(
             repo_config,
             invocation_opts(invocation, [:branch, :limit], opts)
           ) do
      {:ok,
       %Result{
         mode: :json,
         payload: payload,
         json_fields: invocation.json_fields,
         jq: invocation.jq,
         query_label: query_label(repo_config)
       }}
    end
  end

  def run(%Invocation{command: :run_view, log?: true, json_fields: fields, jq: jq}, _repo_config, _opts)
      when is_list(fields) or is_binary(jq) do
    {:error, Error.invalid_invocation("repo-provider run-view --log does not support --json or --jq")}
  end

  def run(%Invocation{command: :run_view} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.run_view(
             repo_config,
             invocation_opts(invocation, [:run_id, :log?], opts)
           ) do
      if invocation.log? do
        {:ok, %Result{mode: :text, payload: payload}}
      else
        {:ok,
         %Result{
           mode: :json,
           payload: payload,
           json_fields: invocation.json_fields,
           jq: invocation.jq,
           query_label: query_label(repo_config)
         }}
      end
    end
  end

  defp query_label(repo_config) do
    case RepoProvider.current_kind(repo_config) do
      "cnb" -> "CNB"
      "github" -> "GitHub"
      _other -> "repo-provider"
    end
  end

  defp invocation_opts(invocation, keys, opts) do
    Keyword.merge(opts, mutation_opts(invocation, keys))
  end

  defp api_opts(invocation, opts) do
    Keyword.merge(
      opts,
      endpoint: invocation.api_endpoint,
      method: invocation.api_method,
      fields: invocation.api_fields
    )
  end

  defp mutation_opts(invocation, keys) do
    keys
    |> Enum.flat_map(fn key ->
      case Map.fetch!(invocation, key) do
        nil -> []
        value -> [{key, value}]
      end
    end)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, false), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp pr_checks_opts(%Invocation{number: nil}, opts), do: opts
  defp pr_checks_opts(%Invocation{number: number}, opts) when is_binary(number), do: Keyword.put(opts, :number, number)

  defp pr_checks_result(check_runs, %Invocation{json?: true} = invocation, repo_config) do
    {:ok,
     %Result{
       mode: :json,
       payload: check_runs,
       jq: invocation.jq,
       query_label: query_label(repo_config),
       exit_code: pr_checks_exit_code(check_runs)
     }}
  end

  defp pr_checks_result(check_runs, _invocation, _repo_config) do
    {:ok,
     %Result{
       mode: :text,
       payload: render_check_summary(check_runs),
       exit_code: pr_checks_exit_code(check_runs)
     }}
  end

  defp run_pr_checks_watch(repo_config, invocation, opts, acc) do
    with {:ok, check_runs} <- RepoProvider.pr_checks(repo_config, pr_checks_opts(invocation, opts)),
         {:ok, output} <- render_pr_checks_iteration(check_runs, invocation, repo_config) do
      updated_acc = [acc, output]
      {pending, failed} = checks_pending_and_failed(check_runs)

      cond do
        failed ->
          {:ok, %Result{mode: :text, payload: IO.iodata_to_binary(updated_acc), exit_code: 1}}

        not pending ->
          {:ok, %Result{mode: :text, payload: IO.iodata_to_binary(updated_acc), exit_code: 0}}

        true ->
          sleep_fn = Keyword.get(opts, :sleep_fn, &Process.sleep/1)
          sleep_fn.(Keyword.get(opts, :watch_poll_ms, @default_watch_poll_ms))
          run_pr_checks_watch(repo_config, invocation, opts, updated_acc)
      end
    end
  end

  defp render_pr_checks_iteration(check_runs, %Invocation{json?: true, jq: jq}, repo_config)
       when is_binary(jq) do
    Query.run(check_runs, jq, query_label(repo_config))
  end

  defp render_pr_checks_iteration(check_runs, %Invocation{json?: true}, _repo_config) do
    {:ok, Jason.encode!(check_runs) <> "\n"}
  end

  defp render_pr_checks_iteration(check_runs, _invocation, _repo_config) do
    {:ok, render_check_summary(check_runs)}
  end

  defp render_check_summary([]), do: "no checks reported\n"

  defp render_check_summary(check_runs) do
    check_runs
    |> Enum.map(fn check ->
      name = check["name"] || check[:name] || "unknown"
      status = check["status"] || check[:status] || "unknown"
      conclusion = check["conclusion"] || check[:conclusion] || "pending"
      summary = check["summary"] || check[:summary] || ""
      suffix = if summary == "", do: "", else: " (#{summary})"
      "#{name}: #{status}/#{conclusion}#{suffix}\n"
    end)
    |> IO.iodata_to_binary()
  end

  defp pr_checks_exit_code(check_runs) do
    case checks_pending_and_failed(check_runs) do
      {false, false} -> 0
      _other -> 1
    end
  end

  defp checks_pending_and_failed(check_runs) do
    Enum.reduce(check_runs, {false, false}, fn check, {pending, failed} ->
      status = check["status"] || check[:status]
      conclusion = check["conclusion"] || check[:conclusion]

      cond do
        status != "completed" ->
          {true, failed}

        conclusion in ["success", "neutral", "skipped"] ->
          {pending, failed}

        true ->
          {pending, true}
      end
    end)
  end
end
