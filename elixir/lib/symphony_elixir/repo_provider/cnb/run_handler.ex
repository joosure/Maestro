defmodule SymphonyElixir.RepoProvider.CNB.RunHandler do
  @moduledoc """
  CI run operations for the CNB adapter.

  Handles listing, viewing, and log rendering of CNB build runs.
  Called by `CNB.Adapter` for all run-related callbacks.
  """

  alias SymphonyElixir.Repo, as: TargetRepo
  alias SymphonyElixir.Repo.Context, as: RepoContext
  alias SymphonyElixir.RepoProvider.CNB.HttpClient
  alias SymphonyElixir.RepoProvider.CNB.Normalizer
  alias SymphonyElixir.RepoProvider.CNB.PullRequestHandler

  @type repo_config :: map()

  # ── Run List ─────────────────────────────────────────────────────

  @spec run_list(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, list(map())} | {:error, term()}
  def run_list(repo, repository, token, opts) do
    with {:ok, branch} <- resolve_run_branch(repo, opts),
         {:ok, runs} <-
           list_runs(repo, repository, token, branch, Keyword.get(opts, :limit, 20), opts) do
      {:ok, runs}
    end
  end

  # ── Run View ─────────────────────────────────────────────────────

  @spec run_view(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, map() | String.t()} | {:error, term()}
  def run_view(repo, repository, token, opts) do
    with {:ok, run_id} <- require_run_id(opts),
         {:ok, run} <- build_run(repo, repository, token, run_id, opts) do
      if Keyword.get(opts, :log?, false) do
        render_run_log(repo, repository, token, run, opts)
      else
        {:ok, run}
      end
    end
  end

  # ── Branch Head SHA ──────────────────────────────────────────────

  @spec branch_head_sha(repo_config(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t() | nil} | {:error, term()}
  def branch_head_sha(repo, repository, token, branch, opts) do
    case PullRequestHandler.resolve_pull_for_branch(repo, repository, token, branch, opts) do
      {:ok, pull} ->
        {:ok, Normalizer.pull_head_sha(pull)}

      {:error, {:cnb_pull_not_found, _branch}} ->
        if branch == current_branch(repo, opts) do
          {:ok, current_head_sha(repo, opts)}
        else
          {:ok, nil}
        end

      {:error, _reason} = error ->
        error
    end
  end

  # ── Private ──────────────────────────────────────────────────────

  defp list_runs(repo, repository, token, branch, limit, opts) do
    with {:ok, sha} <- branch_head_sha(repo, repository, token, branch, opts),
         {:ok, builds} <- fetch_run_builds(repo, repository, token, branch, sha, limit, opts) do
      {:ok, Enum.map(builds, &Normalizer.normalize_run_summary/1)}
    end
  end

  defp fetch_run_builds(repo, repository, token, branch, sha, limit, opts) do
    query = %{"page" => 1, "page_size" => limit, "sourceRef" => branch, "sha" => sha}

    with {:ok, payload} <- fetch_build_logs(repo, repository, token, query, opts),
         {:ok, builds} <- Normalizer.build_log_items(payload) do
      if builds == [] and is_binary(sha) and sha != "" do
        branch_query = %{"page" => 1, "page_size" => limit, "sourceRef" => branch}

        with {:ok, branch_payload} <-
               fetch_build_logs(repo, repository, token, branch_query, opts),
             {:ok, branch_builds} <- Normalizer.build_log_items(branch_payload) do
          {:ok, branch_builds}
        end
      else
        {:ok, builds}
      end
    end
  end

  defp build_run(repo, repository, token, run_id, opts) do
    with {:ok, build} <- fetch_build_log(repo, repository, token, run_id, opts),
         {:ok, status_payload} <-
           HttpClient.fetch_repo_json(repo, repository, token, "/-/build/status/#{run_id}", %{}, opts) do
      pipelines = Normalizer.normalize_pipelines(Map.get(status_payload, "pipelinesStatus"))
      normalized = Normalizer.normalize_run_summary(build)
      raw_status = Map.get(status_payload, "status") || Map.get(normalized, "rawStatus")
      {status, conclusion} = Normalizer.normalize_execution_state(raw_status)

      {:ok,
       normalized
       |> Map.put("pipelines", pipelines)
       |> Map.put("status", status)
       |> Map.put("conclusion", conclusion)
       |> Map.put("rawStatus", raw_status)}
    end
  end

  defp fetch_build_log(repo, repository, token, run_id, opts) do
    with {:ok, payload} <-
           fetch_build_logs(
             repo,
             repository,
             token,
             %{"page" => 1, "page_size" => 1, "sn" => run_id},
             opts
           ),
         {:ok, builds} <- Normalizer.build_log_items(payload) do
      case Enum.find(builds, &(to_string(Map.get(&1, "sn")) == to_string(run_id))) do
        nil -> {:error, {:cnb_run_not_found, run_id}}
        build -> {:ok, build}
      end
    end
  end

  defp fetch_build_logs(repo, repository, token, query, opts) do
    HttpClient.fetch_repo_json(repo, repository, token, "/-/build/logs", query, opts)
  end

  defp fetch_stage_log(repo, repository, token, run_id, pipeline_id, stage_id, opts) do
    HttpClient.fetch_repo_json(
      repo,
      repository,
      token,
      "/-/build/logs/stage/#{run_id}/#{pipeline_id}/#{stage_id}",
      %{},
      opts
    )
  end

  defp render_run_log(repo, repository, token, run, opts) do
    lines =
      [
        "Run #{Map.get(run, "id")}: #{Map.get(run, "rawStatus") || "unknown"}"
      ]
      |> Normalizer.maybe_append_line("Title", Map.get(run, "title"))
      |> Normalizer.maybe_append_line("Branch", Map.get(run, "headBranch"))
      |> Normalizer.maybe_append_line("SHA", Map.get(run, "headSha"))
      |> Normalizer.maybe_append_line("URL", Map.get(run, "url"))

    case Map.get(run, "pipelines") || [] do
      [] ->
        {:ok, Enum.join(lines ++ ["No CNB pipeline stages reported for this run."], "\n") <> "\n"}

      pipelines ->
        with {:ok, rendered_pipelines} <-
               render_pipelines(repo, repository, token, run, pipelines, opts) do
          {:ok, Enum.join(lines ++ rendered_pipelines, "\n") <> "\n"}
        end
    end
  end

  defp render_pipelines(repo, repository, token, run, pipelines, opts) do
    Enum.reduce_while(pipelines, {:ok, []}, fn pipeline, {:ok, acc} ->
      pipeline_name = Map.get(pipeline, "name") || Map.get(pipeline, "id") || "pipeline"
      pipeline_status = Map.get(pipeline, "rawStatus") || "unknown"
      stages = Map.get(pipeline, "stages") || []
      header = ["", "== Pipeline #{pipeline_name} (#{pipeline_status}) =="]

      if stages == [] do
        {:cont, {:ok, acc ++ header ++ ["[no stages reported]"]}}
      else
        case render_stages(repo, repository, token, run, pipeline, stages, opts) do
          {:ok, rendered_stages} -> {:cont, {:ok, acc ++ header ++ rendered_stages}}
          {:error, _reason} = error -> {:halt, error}
        end
      end
    end)
  end

  defp render_stages(repo, repository, token, run, pipeline, stages, opts) do
    Enum.reduce_while(stages, {:ok, []}, fn stage, {:ok, acc} ->
      stage_id = Map.get(stage, "id")
      pipeline_id = Map.get(pipeline, "id")

      if is_nil(stage_id) or is_nil(pipeline_id) do
        {:cont, {:ok, acc}}
      else
        case fetch_stage_log(
               repo,
               repository,
               token,
               to_string(Map.get(run, "id")),
               to_string(pipeline_id),
               to_string(stage_id),
               opts
             ) do
          {:ok, detail} ->
            stage_name = Map.get(detail, "name") || Map.get(stage, "name") || stage_id
            stage_status = Map.get(detail, "status") || Map.get(stage, "rawStatus") || "unknown"
            content = Map.get(detail, "content")

            lines =
              ["-- Stage #{stage_name} (#{stage_status}) --"] ++
                cond do
                  is_list(content) and content != [] ->
                    Enum.map(content, &to_string/1)

                  Map.get(detail, "error") not in [nil, ""] ->
                    ["[stage-error] #{Map.get(detail, "error")}"]

                  true ->
                    ["[no log content]"]
                end

            {:cont, {:ok, acc ++ lines}}

          {:error, _reason} = error ->
            {:halt, error}
        end
      end
    end)
  end

  defp resolve_run_branch(repo, opts) do
    case Keyword.get(opts, :branch) || current_branch(repo, opts) do
      branch when is_binary(branch) and branch != "" -> {:ok, branch}
      _other -> {:error, :cnb_current_branch_unavailable}
    end
  end

  defp require_run_id(opts) do
    case Keyword.get(opts, :run_id) do
      run_id when is_binary(run_id) and run_id != "" -> {:ok, run_id}
      _other -> {:error, :cnb_run_id_required}
    end
  end

  defp current_branch(repo, opts) do
    case TargetRepo.current_branch(RepoContext.path(repo, opts), opts) do
      {:ok, branch} ->
        branch

      {:error, _reason} ->
        nil
    end
  end

  defp current_head_sha(repo, opts) do
    case TargetRepo.head_sha(RepoContext.path(repo, opts), opts) do
      {:ok, sha} ->
        sha

      {:error, _reason} ->
        nil
    end
  end
end
