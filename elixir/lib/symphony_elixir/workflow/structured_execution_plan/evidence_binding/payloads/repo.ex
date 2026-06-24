defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.Payloads.Repo do
  @moduledoc """
  Normalizes repository typed-tool results into evidence payloads.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.RawInput
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.ToolMap

  @repo_commit ToolMap.repo_commit_evidence_kind()
  @repo_push ToolMap.repo_push_evidence_kind()
  @repo_diff ToolMap.repo_diff_evidence_kind()

  @spec normalize(String.t(), term(), term(), term(), map()) :: {:ok, map()}
  def normalize(@repo_commit, _source_kind, source_context, _arguments, payload) do
    data = Map.get(payload, "data", %{})
    status = Map.get(data, "status", %{})

    {:ok,
     RawInput.compact(%{
       "head_sha" => RawInput.string_value(data, "headSha") || RawInput.string_value(status, "headSha"),
       "branch" => RawInput.string_value(status, "branch"),
       "working_tree_clean" => Map.get(status, "clean"),
       "action" => RawInput.string_value(data, "action"),
       "repository" => repo_repository(source_context)
     })}
  end

  def normalize(@repo_push, _source_kind, source_context, _arguments, payload) do
    data = Map.get(payload, "data", %{})

    {:ok,
     RawInput.compact(%{
       "branch" => RawInput.string_value(data, "branch"),
       "remote" => RawInput.string_value(data, "remote"),
       "head_sha" => RawInput.string_value(data, "headSha"),
       "published_head_sha" => RawInput.string_value(data, "publishedHeadSha"),
       "repository" => repo_repository(source_context)
     })}
  end

  def normalize(@repo_diff, _source_kind, _source_context, arguments, payload) do
    data = Map.get(payload, "data", %{})
    status = Map.get(data, "status", %{})

    {:ok,
     RawInput.compact(%{
       "check" => Map.has_key?(data, "diffCheck") and not is_nil(Map.get(data, "diffCheck")),
       "head_sha" => RawInput.string_value(status, "headSha"),
       "cwd" => RawInput.string_value(status, "root") || RawInput.string_value(status, "path"),
       "args" => arguments |> RawInput.value("args") |> RawInput.string_list()
     })}
  end

  def normalize(_evidence_kind, _source_kind, _source_context, _arguments, _payload), do: {:ok, %{}}

  defp repo_repository(source_context) do
    RawInput.string_value(source_context, "repository") || RawInput.string_value(source_context, "repo")
  end
end
