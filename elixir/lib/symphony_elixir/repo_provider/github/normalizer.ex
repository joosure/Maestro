defmodule SymphonyElixir.RepoProvider.GitHub.Normalizer do
  @moduledoc """
  Data normalization layer for the GitHub repo-provider adapter.

  Transforms raw GitHub CLI JSON payloads into the canonical format
  expected by the `RepoProvider` facade. All functions are pure data
  transforms with no side-effects.
  """

  # ── Run normalization ──────────────────────────────────────────

  @spec normalize_run_detail(map()) :: map()
  def normalize_run_detail(run) when is_map(run) do
    normalized = normalize_run_summary(run)
    jobs = normalize_jobs(Map.get(run, "jobs", run[:jobs]))

    {job_success_count, job_fail_count} =
      Enum.reduce(jobs, {0, 0}, fn job, {success_count, fail_count} ->
        case Map.get(job, "conclusion") do
          "success" -> {success_count + 1, fail_count}
          nil -> {success_count, fail_count}
          _other -> {success_count, fail_count + 1}
        end
      end)

    normalized
    |> Map.put("jobs", jobs)
    |> Map.put("jobTotalCount", length(jobs))
    |> Map.put("jobSuccessCount", job_success_count)
    |> Map.put("jobFailCount", job_fail_count)
  end

  @spec normalize_run_summary(map()) :: map()
  def normalize_run_summary(run) when is_map(run) do
    status = field_value(run, "status", :status)
    conclusion = field_value(run, "conclusion", :conclusion)
    {normalized_status, normalized_conclusion} = normalize_run_state(status, conclusion)

    %{
      "id" => field_value(run, "databaseId", :databaseId),
      "url" => field_value(run, "url", :url),
      "title" => field_value(run, "displayTitle", :displayTitle) || field_value(run, "name", :name) || "",
      "status" => normalized_status,
      "conclusion" => normalized_conclusion,
      "rawStatus" => raw_run_status(status, conclusion),
      "headBranch" => field_value(run, "headBranch", :headBranch),
      "headSha" => field_value(run, "headSha", :headSha),
      "event" => field_value(run, "event", :event),
      "createdAt" => field_value(run, "createdAt", :createdAt),
      "startedAt" => field_value(run, "startedAt", :startedAt),
      "updatedAt" => field_value(run, "updatedAt", :updatedAt),
      "workflowName" => field_value(run, "workflowName", :workflowName),
      "number" => field_value(run, "number", :number),
      "attempt" => field_value(run, "attempt", :attempt)
    }
  end

  def normalize_run_summary(_run), do: %{}

  # ── Job / Step normalization ───────────────────────────────────

  @spec normalize_jobs(list() | term()) :: list(map())
  def normalize_jobs(jobs) when is_list(jobs) do
    Enum.flat_map(jobs, fn
      job when is_map(job) -> [normalize_job(job)]
      _other -> []
    end)
  end

  def normalize_jobs(_jobs), do: []

  @spec normalize_job(map()) :: map()
  def normalize_job(job) when is_map(job) do
    status = field_value(job, "status", :status)
    conclusion = field_value(job, "conclusion", :conclusion)
    {normalized_status, normalized_conclusion} = normalize_run_state(status, conclusion)

    %{
      "id" => field_value(job, "databaseId", :databaseId),
      "name" => field_value(job, "name", :name) || "unknown",
      "status" => normalized_status,
      "conclusion" => normalized_conclusion,
      "rawStatus" => raw_run_status(status, conclusion),
      "startedAt" => field_value(job, "startedAt", :startedAt),
      "completedAt" => field_value(job, "completedAt", :completedAt),
      "url" => field_value(job, "url", :url),
      "steps" => normalize_steps(field_value(job, "steps", :steps))
    }
  end

  @spec normalize_steps(list() | term()) :: list(map())
  def normalize_steps(steps) when is_list(steps) do
    Enum.flat_map(steps, fn
      step when is_map(step) ->
        status = field_value(step, "status", :status)
        conclusion = field_value(step, "conclusion", :conclusion)
        {normalized_status, normalized_conclusion} = normalize_run_state(status, conclusion)

        [
          %{
            "number" => field_value(step, "number", :number),
            "name" => field_value(step, "name", :name) || "unknown",
            "status" => normalized_status,
            "conclusion" => normalized_conclusion,
            "startedAt" => field_value(step, "startedAt", :startedAt),
            "completedAt" => field_value(step, "completedAt", :completedAt)
          }
        ]

      _other ->
        []
    end)
  end

  def normalize_steps(_steps), do: []

  # ── Check run normalization ────────────────────────────────────

  @spec normalize_check_run(map()) :: list(map())
  def normalize_check_run(check) when is_map(check) do
    bucket =
      check
      |> Map.get("bucket", check[:bucket] || "")
      |> to_string()
      |> String.downcase()

    state =
      check
      |> Map.get("state", check[:state] || "")
      |> to_string()
      |> String.downcase()

    {status, conclusion} =
      case bucket do
        "pass" -> {"completed", "success"}
        "fail" -> {"completed", "failure"}
        "pending" -> {"in_progress", nil}
        "skipping" -> {"completed", "skipped"}
        "cancel" -> {"completed", "cancelled"}
        _other -> normalize_check_state(state)
      end

    [
      %{
        "name" => Map.get(check, "name", check[:name] || "unknown"),
        "status" => status,
        "conclusion" => conclusion,
        "created_at" => Map.get(check, "startedAt", check[:startedAt]),
        "started_at" => Map.get(check, "startedAt", check[:startedAt]),
        "completed_at" => Map.get(check, "completedAt", check[:completedAt]),
        "details_url" => Map.get(check, "link", check[:link]),
        "summary" => Map.get(check, "description", check[:description])
      }
    ]
  end

  def normalize_check_run(_check), do: []

  # ── Comment normalization ──────────────────────────────────────

  @spec normalize_issue_comment(map()) :: map()
  def normalize_issue_comment(comment) when is_map(comment) do
    %{
      "id" => field_value(comment, "id", :id),
      "body" => field_value(comment, "body", :body) || "",
      "created_at" => field_value(comment, "created_at", :created_at),
      "updated_at" => field_value(comment, "updated_at", :updated_at),
      "user" => normalize_user(field_value(comment, "user", :user) || %{})
    }
  end

  @spec normalize_review(map()) :: map()
  def normalize_review(review) when is_map(review) do
    %{
      "id" => field_value(review, "id", :id),
      "body" => field_value(review, "body", :body) || "",
      "created_at" => field_value(review, "submitted_at", :submitted_at) || field_value(review, "created_at", :created_at),
      "submitted_at" => field_value(review, "submitted_at", :submitted_at) || field_value(review, "created_at", :created_at),
      "state" => review |> field_value("state", :state) |> to_string() |> String.upcase(),
      "user" => normalize_user(field_value(review, "user", :user) || %{})
    }
  end

  @spec normalize_review_comment(map()) :: map()
  def normalize_review_comment(comment) when is_map(comment) do
    %{
      "id" => field_value(comment, "id", :id),
      "body" => field_value(comment, "body", :body) || "",
      "created_at" => field_value(comment, "created_at", :created_at),
      "updated_at" => field_value(comment, "updated_at", :updated_at),
      "path" => field_value(comment, "path", :path),
      "commit_id" => field_value(comment, "commit_id", :commit_id),
      "in_reply_to_id" => field_value(comment, "in_reply_to_id", :in_reply_to_id),
      "pull_request_review_id" => field_value(comment, "pull_request_review_id", :pull_request_review_id),
      "user" => normalize_user(field_value(comment, "user", :user) || %{})
    }
  end

  @spec normalize_user(map() | term()) :: map()
  def normalize_user(user) when is_map(user) do
    %{
      "login" => field_value(user, "login", :login) || "",
      "type" => field_value(user, "type", :type) || "User"
    }
  end

  def normalize_user(_user), do: %{"login" => "", "type" => "User"}

  @spec normalize_check_state(String.t()) :: {String.t(), String.t() | nil}
  def normalize_check_state(state) when is_binary(state) do
    normalized = String.downcase(state)

    cond do
      normalized in ["success", "passed", "completed"] ->
        {"completed", "success"}

      normalized == "neutral" ->
        {"completed", "neutral"}

      normalized in ["skip", "skipped"] ->
        {"completed", "skipped"}

      normalized in ["cancel", "cancelled", "canceled"] ->
        {"completed", "cancelled"}

      normalized in ["failure", "failed", "error", "timed_out", "action_required"] ->
        {"completed", "failure"}

      normalized in [
        "pending",
        "queued",
        "created",
        "running",
        "in_progress",
        "checking",
        "requested",
        "waiting",
        ""
      ] ->
        {"in_progress", nil}

      true ->
        {"completed", normalized}
    end
  end

  # ── State normalization ────────────────────────────────────────

  @spec normalize_run_state(term(), term()) :: {String.t(), String.t() | nil}
  def normalize_run_state(status, conclusion) do
    normalized_status = normalize_string(status)
    normalized_conclusion = map_run_conclusion(conclusion)

    cond do
      normalized_status in ["queued", "in_progress", "requested", "waiting", "pending", ""] ->
        {"in_progress", nil}

      normalized_status == "completed" ->
        {"completed", normalized_conclusion}

      normalized_status in [
        "cancelled",
        "canceled",
        "failure",
        "success",
        "neutral",
        "skipped",
        "timed_out",
        "action_required",
        "stale",
        "startup_failure"
      ] ->
        {"completed", map_run_conclusion(normalized_status)}

      true ->
        {"completed", normalized_conclusion || normalized_status}
    end
  end

  @spec map_run_conclusion(term()) :: String.t() | nil
  def map_run_conclusion(nil), do: nil

  def map_run_conclusion(value) do
    case normalize_string(value) do
      "" -> nil
      "cancel" -> "cancelled"
      "canceled" -> "cancelled"
      "cancelled" -> "cancelled"
      "failure" -> "failure"
      "failed" -> "failure"
      "error" -> "failure"
      other -> other
    end
  end

  @spec raw_run_status(term(), term()) :: String.t()
  def raw_run_status(status, conclusion) do
    normalized_status = normalize_string(status)
    normalized_conclusion = map_run_conclusion(conclusion)

    cond do
      normalized_status == "completed" and is_binary(normalized_conclusion) ->
        normalized_conclusion

      normalized_status != "" ->
        normalized_status

      is_binary(normalized_conclusion) ->
        normalized_conclusion

      true ->
        "unknown"
    end
  end

  # ── Log rendering ──────────────────────────────────────────────

  @spec render_run_log(map(), String.t()) :: String.t()
  def render_run_log(run, raw_log) when is_map(run) and is_binary(raw_log) do
    [
      "Run #{Map.get(run, "id")}: #{Map.get(run, "rawStatus") || "unknown"}"
    ]
    |> maybe_append_line("Title", Map.get(run, "title"))
    |> maybe_append_line("Workflow", Map.get(run, "workflowName"))
    |> maybe_append_line("Branch", Map.get(run, "headBranch"))
    |> maybe_append_line("SHA", Map.get(run, "headSha"))
    |> maybe_append_line("URL", Map.get(run, "url"))
    |> then(fn header_lines ->
      log_body =
        raw_log
        |> String.trim_trailing("\n")
        |> case do
          "" -> "No GitHub log output reported for this run."
          output -> output
        end

      Enum.join(header_lines, "\n") <> "\n\n" <> log_body <> "\n"
    end)
  end

  # ── Utility ────────────────────────────────────────────────────

  @spec field_value(map(), String.t(), atom()) :: term()
  def field_value(map, string_key, atom_key) when is_map(map) do
    Map.get(map, string_key, Map.get(map, atom_key))
  end

  @spec normalize_string(term()) :: String.t()
  def normalize_string(nil), do: ""
  def normalize_string(value), do: value |> to_string() |> String.trim() |> String.downcase()

  @spec maybe_append_line(list(), String.t(), term()) :: list()
  def maybe_append_line(lines, _label, nil), do: lines
  def maybe_append_line(lines, _label, ""), do: lines
  def maybe_append_line(lines, label, value), do: lines ++ ["#{label}: #{value}"]
end
