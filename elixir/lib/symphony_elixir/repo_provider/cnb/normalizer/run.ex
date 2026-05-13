defmodule SymphonyElixir.RepoProvider.CNB.Normalizer.Run do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CNB.Normalizer.Values

  @spec normalize_run_summary(map()) :: map()
  def normalize_run_summary(build) do
    raw_status = Map.get(build, "status")
    {status, conclusion} = normalize_execution_state(raw_status)

    %{
      "id" => Values.json_id(Map.get(build, "sn")),
      "url" => Map.get(build, "buildLogUrl"),
      "title" => Map.get(build, "title") || Map.get(build, "commitTitle") || "",
      "status" => status,
      "conclusion" => conclusion,
      "rawStatus" => raw_status,
      "headBranch" => Map.get(build, "sourceRef"),
      "headSha" => Map.get(build, "sha"),
      "event" => Map.get(build, "event"),
      "eventUrl" => Map.get(build, "eventUrl"),
      "createdAt" => Map.get(build, "createTime"),
      "durationMs" => Map.get(build, "duration"),
      "pipelineTotalCount" => Map.get(build, "pipelineTotalCount"),
      "pipelineSuccessCount" => Map.get(build, "pipelineSuccessCount"),
      "pipelineFailCount" => Map.get(build, "pipelineFailCount")
    }
  end

  @spec normalize_pipelines(map() | term()) :: list(map())
  def normalize_pipelines(pipelines_status) when is_map(pipelines_status) do
    pipelines_status
    |> Enum.sort_by(fn {pipeline_id, _info} -> to_string(pipeline_id) end)
    |> Enum.flat_map(fn {pipeline_id, info} ->
      if is_map(info) do
        {status, conclusion} = normalize_execution_state(Map.get(info, "status"))

        [
          %{
            "id" => to_string(pipeline_id),
            "name" => Map.get(info, "name"),
            "status" => status,
            "conclusion" => conclusion,
            "rawStatus" => Map.get(info, "status"),
            "durationMs" => Map.get(info, "duration"),
            "labels" => if(is_list(Map.get(info, "labels")), do: Map.get(info, "labels"), else: []),
            "stages" => normalize_stages(Map.get(info, "stages"))
          }
        ]
      else
        []
      end
    end)
  end

  def normalize_pipelines(_pipelines_status), do: []

  @spec normalize_stages(list() | term()) :: list(map())
  def normalize_stages(stages) when is_list(stages) do
    Enum.flat_map(stages, fn
      stage when is_map(stage) ->
        {status, conclusion} = normalize_execution_state(Map.get(stage, "status"))

        [
          %{
            "id" => Map.get(stage, "id"),
            "name" => Map.get(stage, "name"),
            "status" => status,
            "conclusion" => conclusion,
            "rawStatus" => Map.get(stage, "status"),
            "durationMs" => Map.get(stage, "duration")
          }
        ]

      _stage ->
        []
    end)
  end

  def normalize_stages(_stages), do: []

  @spec normalize_execution_state(term()) :: {String.t(), String.t() | nil}
  def normalize_execution_state(raw_status) do
    normalized =
      raw_status
      |> to_string()
      |> String.trim()
      |> String.downcase()

    cond do
      normalized in ["success", "passed"] ->
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
        "start",
        ""
      ] ->
        {"in_progress", nil}

      true ->
        {"completed", normalized}
    end
  end

  @spec build_log_items(map()) :: {:ok, list(map())} | {:error, term()}
  def build_log_items(%{"data" => items}) when is_list(items) do
    {:ok, Enum.filter(items, &is_map/1)}
  end

  def build_log_items(_payload), do: {:error, {:cnb_unknown_payload, :build_logs, nil}}

  @spec maybe_append_line(list(), String.t(), term()) :: list()
  def maybe_append_line(lines, _label, nil), do: lines
  def maybe_append_line(lines, _label, ""), do: lines
  def maybe_append_line(lines, label, value), do: lines ++ ["#{label}: #{value}"]
end
