defmodule SymphonyElixir.WorkflowValidatorTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.Profiles.{CodingPrDelivery, RequirementAnalysis}
  alias SymphonyElixir.Workflow.Validator

  test "accepts a complete effective coding workflow" do
    assert :ok == Validator.validate_workflow(:global, coding_workflow())
  end

  test "rejects unsupported workflow profile config" do
    workflow =
      coding_workflow(%{
        profile: %{"kind" => "unsupported", "version" => 1, "options" => %{}}
      })

    assert {:error, {:invalid_workflow_profile, {:unsupported_workflow_profile, "unsupported", 1}}} =
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects raw-state maps with route keys outside the active profile vocabulary" do
    raw_state_by_route_key =
      CodingPrDelivery.default_raw_state_by_route_key()
      |> Map.put(:qa_review, "qa_review")

    workflow = coding_workflow(%{raw_state_by_route_key: raw_state_by_route_key})

    assert {:error, {:invalid_raw_state_route_key, :global, :qa_review}} =
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects raw-state maps with blank raw tracker states" do
    raw_state_by_route_key =
      CodingPrDelivery.default_raw_state_by_route_key()
      |> Map.put(:review, " ")

    workflow = coding_workflow(%{raw_state_by_route_key: raw_state_by_route_key})

    assert {:error, {:invalid_raw_state_by_route_key_value, :global, :review, " "}} =
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects effective workflows missing raw states for required routes" do
    raw_state_by_route_key =
      CodingPrDelivery.default_raw_state_by_route_key()
      |> Map.delete(:review)

    workflow = coding_workflow(%{raw_state_by_route_key: raw_state_by_route_key})

    assert {:error, {:missing_raw_state_for_route_key, :global, :review}} =
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects dispatchable routes whose raw states are not active" do
    workflow = coding_workflow(%{active_states: ["planning", "merging", "rework"]})

    assert {:error, {:raw_state_not_active, :global, :developing, "developing"}} =
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects terminal routes whose raw states are not terminal" do
    workflow = coding_workflow(%{terminal_states: ["rejected"]})

    assert {:error, {:raw_state_not_terminal, :global, :resolved, "resolved"}} =
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects raw states mapped to unexpected lifecycle phases" do
    state_phase_map =
      coding_state_phase_map()
      |> Map.put("planning", "human_review")

    workflow = coding_workflow(%{state_phase_map: state_phase_map})

    assert {:error, {:invalid_raw_state_lifecycle_phase, :global, :planning, "planning", "human_review", "todo"}} =
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects policy maps with route keys outside the active profile vocabulary" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> Map.put(:qa_review, %{action: :stop})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:invalid_route_policy_key, :global, :qa_review}} =
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects unsupported policy entry fields" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> put_in([:developing], %{"unexpected_field" => "land", action: :dispatch})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:unsupported_route_policy_field, :global, :developing, "unexpected_field"}} =
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects transition targets on non-transition policy actions" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> put_in([:developing], %{action: :dispatch, transition_target: :review})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:invalid_route_policy_transition_target_action, :global, :developing, :dispatch}} =
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects transition targets that are raw tracker states instead of route keys" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> put_in([:planning], %{action: :transition, transition_target: "status_5"})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:invalid_route_policy_transition_target_key, :global, :planning, "status_5"}} =
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects transition actions without transition targets" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> put_in([:planning], %{action: :transition})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:missing_route_policy_transition_target, :global, :planning}} =
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects policy transition cycles" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> put_in([:planning], %{action: :transition, transition_target: :planning})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:route_policy_transition_target_cycle, :global, :planning, :planning}} =
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects transition_then_dispatch targets that do not map to dispatchable phases" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> put_in([:planning], %{action: :transition_then_dispatch, transition_target: :review})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:invalid_route_policy_transition_phase, :global, :planning, :review, "human_review"}} =
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects unsupported execution profiles for the active workflow profile" do
    policy_by_route_key =
      RequirementAnalysis.default_policy_by_route_key()
      |> put_in([:analyzing], %{action: :dispatch, execution_profile: "land"})

    workflow = requirement_analysis_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:unsupported_route_policy_execution_profile, :global, :analyzing, "land"}} =
             Validator.validate_workflow(:global, workflow)
  end

  test "validates raw policy override entries before normalization" do
    profile_context = ProfileRegistry.resolve!(nil)

    assert {:error, {:invalid_route_policy_key, "feature", "unknown_route"}} =
             Validator.validate_policy_by_route_key_entries(
               "feature",
               %{"unknown_route" => %{"action" => "stop"}},
               profile_context
             )
  end

  defp coding_workflow(overrides \\ %{}) do
    workflow_for_profile(
      CodingPrDelivery,
      ["planning", "developing", "merging", "rework"],
      ["resolved", "rejected"],
      overrides
    )
  end

  defp requirement_analysis_workflow(overrides) do
    workflow_for_profile(
      RequirementAnalysis,
      ["intake", "analyzing"],
      ["ready", "rejected"],
      overrides
    )
  end

  defp workflow_for_profile(profile_module, active_states, terminal_states, overrides) do
    options = profile_module.default_options()

    %{
      profile: %{
        "kind" => profile_module.kind(),
        "version" => profile_module.version(),
        "options" => options
      },
      active_states: active_states,
      terminal_states: terminal_states,
      state_phase_map: state_phase_map(profile_module),
      raw_state_by_route_key: profile_module.default_raw_state_by_route_key(),
      policy_by_route_key: profile_module.default_policy_by_route_key(options)
    }
    |> Map.merge(overrides)
  end

  defp coding_state_phase_map, do: state_phase_map(CodingPrDelivery)

  defp state_phase_map(profile_module) do
    raw_state_by_route_key = profile_module.default_raw_state_by_route_key()
    lifecycle_phase_by_route_key = profile_module.lifecycle_phase_by_route_key()

    Map.new(raw_state_by_route_key, fn {route_key, raw_state} ->
      {raw_state, Map.fetch!(lifecycle_phase_by_route_key, route_key)}
    end)
  end
end
