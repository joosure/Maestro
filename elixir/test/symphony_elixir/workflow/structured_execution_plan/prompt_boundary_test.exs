defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.PromptBoundaryTest do
  use ExUnit.Case, async: true

  @structured_plan_core_dir Path.expand("../../../../lib/symphony_elixir/workflow/structured_execution_plan", __DIR__)
  @profiles_dir Path.expand("../../../../lib/symphony_elixir/workflow/profiles", __DIR__)

  test "structured plan code does not depend on workflow prompt modules" do
    forbidden_patterns = [
      "SymphonyElixir.Workflow.Prompt",
      "Workflow.Prompt",
      "PromptBuilder",
      "Prompt.Builder"
    ]

    for {path, source} <- structured_plan_sources_with_profile_adoptions(),
        pattern <- forbidden_patterns do
      refute source =~ pattern, "#{Path.relative_to_cwd(path)} references #{pattern}"
    end
  end

  test "structured plan core does not parse Workpad text as authoritative state" do
    forbidden_patterns = [
      {~r/\btracker_comments\b/, "tracker comments must not be inspected by structured plan core"},
      {~r/\bcomment_body\b/i, "comment body must not be treated as structured plan input"},
      {~r/\bworkpad_body\b/i, "Workpad body must remain rendered output, not structured plan input"},
      {~r/\bparse_?workpad\b/i, "Workpad parser must not become a structured plan authority"},
      {~r/\bimport_?workpad\b/i, "Workpad import must not become a structured plan authority"},
      {~r/\bingest_?workpad\b/i, "Workpad ingestion must not become a structured plan authority"},
      {~r/\bhydrate_?workpad\b/i, "Workpad hydration must not become a structured plan authority"}
    ]

    for {path, source} <- structured_plan_core_sources(),
        {pattern, message} <- forbidden_patterns do
      refute Regex.match?(pattern, source), "#{Path.relative_to_cwd(path)} violates boundary: #{message}"
    end
  end

  defp structured_plan_sources_with_profile_adoptions do
    structured_plan_core_sources() ++ profile_adoption_sources()
  end

  defp structured_plan_core_sources do
    @structured_plan_core_dir
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> read_sources()
  end

  defp profile_adoption_sources do
    @profiles_dir
    |> Path.join("**/structured_execution_plan.ex")
    |> Path.wildcard()
    |> read_sources()
  end

  defp read_sources(paths), do: Enum.map(paths, &{&1, File.read!(&1)})
end
