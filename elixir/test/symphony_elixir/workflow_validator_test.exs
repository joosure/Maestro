defmodule SymphonyElixir.WorkflowValidatorTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile, as: CodingPrDelivery
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.Profiles.RequirementAnalysis
  alias SymphonyElixir.Workflow.RoutePolicy
  alias SymphonyElixir.Workflow.RouteRef
  alias SymphonyElixir.Workflow.Validator

  test "accepts a complete effective coding workflow" do
    assert :ok == Validator.validate_workflow(:global, coding_workflow())
  end

  test "rejects unsupported workflow profile config" do
    workflow =
      coding_workflow(%{
        profile: %{"kind" => "unsupported", "version" => 1, "options" => %{}}
      })

    assert {:error, {:invalid_workflow_profile, {:unsupported_workflow_profile, "unsupported", 1}}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects raw-state maps with route keys outside the active profile vocabulary" do
    raw_state_by_route_key =
      RoutePolicy.identity_raw_state_by_route_key(CodingPrDelivery)
      |> Map.put(:qa_review, "qa_review")

    workflow = coding_workflow(%{raw_state_by_route_key: raw_state_by_route_key})

    assert {:error, {:invalid_raw_state_route_key, :global, invalid_route_key(CodingPrDelivery, :qa_review)}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects effective raw-state maps with string route keys" do
    raw_state_by_route_key =
      RoutePolicy.identity_raw_state_by_route_key(CodingPrDelivery)
      |> Map.delete(:rework)
      |> Map.put("rework", "Rework")

    workflow = coding_workflow(%{raw_state_by_route_key: raw_state_by_route_key})

    assert {:error, {:invalid_raw_state_route_key, :global, {:invalid_workflow_route_key, "coding_pr_delivery", 1, "rework"}}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects raw-state maps with blank raw tracker states" do
    raw_state_by_route_key =
      RoutePolicy.identity_raw_state_by_route_key(CodingPrDelivery)
      |> Map.put(:review, " ")

    workflow = coding_workflow(%{raw_state_by_route_key: raw_state_by_route_key})

    assert {:error, {:invalid_raw_state_by_route_key_value, :global, coding_route_ref(:review), " "}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects effective workflows missing raw states for required routes" do
    raw_state_by_route_key =
      RoutePolicy.identity_raw_state_by_route_key(CodingPrDelivery)
      |> Map.delete(:review)

    workflow = coding_workflow(%{raw_state_by_route_key: raw_state_by_route_key})

    assert {:error, {:missing_raw_state_for_route_key, :global, coding_route_ref(:review)}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "accepts disabled routes without raw tracker states" do
    raw_state_by_route_key =
      RoutePolicy.identity_raw_state_by_route_key(CodingPrDelivery)
      |> Map.delete(:rework)

    state_phase_map =
      coding_state_phase_map()
      |> Map.delete("rework")

    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> put_in([:rework], %{action: :disabled})

    workflow =
      coding_workflow(%{
        active_states: ["planning", "developing", "merging"],
        raw_state_by_route_key: raw_state_by_route_key,
        state_phase_map: state_phase_map,
        policy_by_route_key: policy_by_route_key
      })

    assert :ok == Validator.validate_workflow(:global, workflow)
  end

  test "rejects effective policy actions that are not atom-valued" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> put_in([:rework], %{action: "disabled"})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:invalid_route_policy_action, :global, coding_route_ref(:rework), "disabled"}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects effective policy entries with string fields" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> put_in([:developing], %{"action" => :dispatch})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:unsupported_route_policy_field, :global, coding_route_ref(:developing), "action"}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects effective policy maps with string route keys" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> Map.delete(:rework)
      |> Map.put("rework", %{action: :disabled})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:invalid_route_policy_key, :global, {:invalid_workflow_route_key, "coding_pr_delivery", 1, "rework"}}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects dispatchable routes whose raw states are not active" do
    workflow = coding_workflow(%{active_states: ["planning", "merging", "rework"]})

    assert {:error, {:raw_state_not_active, :global, coding_route_ref(:developing), "developing"}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects terminal routes whose raw states are not terminal" do
    workflow = coding_workflow(%{terminal_states: ["rejected"]})

    assert {:error, {:raw_state_not_terminal, :global, coding_route_ref(:resolved), "resolved"}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects raw states mapped to unexpected lifecycle phases" do
    state_phase_map =
      coding_state_phase_map()
      |> Map.put("planning", "human_review")

    workflow = coding_workflow(%{state_phase_map: state_phase_map})

    assert {:error, {:invalid_raw_state_lifecycle_phase, :global, coding_route_ref(:planning), "planning", "human_review", "todo"}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects policy maps with route keys outside the active profile vocabulary" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> Map.put(:qa_review, %{action: :stop})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:invalid_route_policy_key, :global, invalid_route_key(CodingPrDelivery, :qa_review)}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects unsupported policy entry fields" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> put_in([:developing], %{"unexpected_field" => "land", action: :dispatch})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:unsupported_route_policy_field, :global, coding_route_ref(:developing), "unexpected_field"}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects transition targets on non-transition policy actions" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> put_in([:developing], %{action: :dispatch, transition_target: :review})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:invalid_route_policy_transition_target_action, :global, coding_route_ref(:developing), :dispatch}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects transition targets that are raw tracker states instead of route keys" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> put_in([:planning], %{action: :transition, transition_target: "status_5"})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:invalid_route_policy_transition_target_key, :global, coding_route_ref(:planning), invalid_route_key(CodingPrDelivery, "status_5")}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects transition actions without transition targets" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> put_in([:planning], %{action: :transition})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:missing_route_policy_transition_target, :global, coding_route_ref(:planning)}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects policy transition cycles" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> put_in([:planning], %{action: :transition, transition_target: :planning})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:route_policy_transition_target_cycle, :global, coding_route_ref(:planning), coding_route_ref(:planning)}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects transition_then_dispatch targets that do not map to dispatchable phases" do
    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key()
      |> put_in([:planning], %{action: :transition_then_dispatch, transition_target: :review})

    workflow = coding_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:invalid_route_policy_transition_phase, :global, coding_route_ref(:planning), coding_route_ref(:review), "human_review"}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects unsupported execution profiles for the active workflow profile" do
    policy_by_route_key =
      RequirementAnalysis.default_policy_by_route_key()
      |> put_in([:analyzing], %{action: :dispatch, execution_profile: "land"})

    workflow = requirement_analysis_workflow(%{policy_by_route_key: policy_by_route_key})

    assert {:error, {:unsupported_route_policy_execution_profile, :global, requirement_analysis_route_ref(:analyzing), "land"}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "rejects merging execution profiles that are not declared by the active profile" do
    options = %{"execution_profiles" => %{"allowed" => ["ship"]}}

    policy_by_route_key =
      CodingPrDelivery.default_policy_by_route_key(options)
      |> put_in([:merging], %{action: :dispatch, execution_profile: "land"})

    workflow =
      coding_workflow(%{
        profile: %{
          "kind" => CodingPrDelivery.kind(),
          "version" => CodingPrDelivery.version(),
          "options" => options
        },
        policy_by_route_key: policy_by_route_key
      })

    assert {:error, {:unsupported_route_policy_execution_profile, :global, coding_route_ref(:merging), "land"}} ==
             Validator.validate_workflow(:global, workflow)
  end

  test "validates raw policy override entries before normalization" do
    profile_context = ProfileRegistry.resolve!(nil)

    assert {:error, {:invalid_route_policy_key, "feature", invalid_route_key(CodingPrDelivery, "unknown_route")}} ==
             Validator.validate_policy_by_route_key_entries(
               "feature",
               %{"unknown_route" => %{"action" => "stop"}},
               profile_context
             )
  end

  test "rejects atom route keys in raw route-map config entries" do
    profile_context = ProfileRegistry.resolve!(nil)
    invalid_atom_route_key = {:invalid_workflow_route_key, "coding_pr_delivery", 1, :rework}

    assert {:error, {:invalid_raw_state_route_key, "feature", ^invalid_atom_route_key}} =
             Validator.validate_raw_state_by_route_key_entries(
               "feature",
               %{rework: "Rework"},
               profile_context
             )

    assert {:error, {:invalid_route_policy_key, "feature", ^invalid_atom_route_key}} =
             Validator.validate_policy_by_route_key_entries(
               "feature",
               %{rework: %{"action" => "disabled"}},
               profile_context
             )
  end

  test "rejects atom fields in raw policy config entries" do
    profile_context = ProfileRegistry.resolve!(nil)

    assert {:error, {:unsupported_route_policy_field, "feature", coding_route_ref(:rework), :action}} ==
             Validator.validate_policy_by_route_key_entries(
               "feature",
               %{"rework" => %{action: :disabled}},
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
      raw_state_by_route_key: RoutePolicy.identity_raw_state_by_route_key(profile_module),
      policy_by_route_key: profile_module.default_policy_by_route_key(options)
    }
    |> Map.merge(overrides)
  end

  defp coding_state_phase_map, do: state_phase_map(CodingPrDelivery)

  defp coding_route_ref(route_key), do: route_ref(CodingPrDelivery, route_key)

  defp requirement_analysis_route_ref(route_key), do: route_ref(RequirementAnalysis, route_key)

  defp route_ref(profile_module, route_key) do
    %RouteRef{
      profile_kind: profile_module.kind(),
      profile_version: profile_module.version(),
      route_key: route_key
    }
  end

  defp invalid_route_key(profile_module, route_key) do
    {:invalid_workflow_route_key, profile_module.kind(), profile_module.version(), route_key}
  end

  defp state_phase_map(profile_module) do
    raw_state_by_route_key = RoutePolicy.identity_raw_state_by_route_key(profile_module)
    lifecycle_phase_by_route_key = profile_module.lifecycle_phase_by_route_key()

    Map.new(raw_state_by_route_key, fn {route_key, raw_state} ->
      {raw_state, Map.fetch!(lifecycle_phase_by_route_key, route_key)}
    end)
  end
end
