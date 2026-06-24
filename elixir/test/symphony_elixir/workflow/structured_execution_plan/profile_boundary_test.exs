defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProfileBoundaryTest do
  use ExUnit.Case, async: true

  @structured_plan_core_dir Path.expand("../../../../lib/symphony_elixir/workflow/structured_execution_plan", __DIR__)
  @profile_specific_directories ~w(profile_templates profile_adoption profiles)

  @concrete_profiles %{
    "coding_pr_delivery" => "CodingPrDelivery",
    "requirement_analysis" => "RequirementAnalysis",
    "requirement_refinement" => "RequirementRefinement",
    "review_routing" => "ReviewRouting",
    "triage" => "Triage"
  }

  test "structured execution plan core does not own profile-specific adoption templates" do
    for directory <- @profile_specific_directories do
      refute File.dir?(Path.join(@structured_plan_core_dir, directory)),
             "structured execution plan core must not contain profile-specific #{directory}/"
    end
  end

  test "structured execution plan core does not reference concrete profile adoption modules" do
    for {path, source} <- core_sources(), pattern <- forbidden_profile_patterns() do
      refute source =~ pattern, "#{Path.relative_to_cwd(path)} references #{pattern}"
    end
  end

  defp core_sources do
    @structured_plan_core_dir
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.map(&{&1, File.read!(&1)})
  end

  defp forbidden_profile_patterns do
    static_patterns = [
      "Workflow.StructuredExecutionPlan.ProfileTemplates",
      "Workflow.StructuredExecutionPlan.ProfileAdoption",
      "ProfileTemplates."
    ]

    profile_patterns =
      Enum.flat_map(@concrete_profiles, fn {profile_kind, profile_module} ->
        [
          profile_kind,
          "Workflow.Profiles.#{profile_module}",
          "Profiles.#{profile_module}"
        ]
      end)

    static_patterns ++ profile_patterns
  end
end
