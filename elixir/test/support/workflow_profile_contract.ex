defmodule SymphonyElixir.WorkflowProfileContract do
  @moduledoc false

  defmacro __using__(opts) do
    profile =
      opts
      |> Keyword.fetch!(:profile)
      |> Macro.expand(__CALLER__)

    # credo:disable-for-next-line Credo.Check.Refactor.LongQuoteBlocks
    quote do
      alias SymphonyElixir.Workflow.{
        ExecutionProfileRegistry,
        Lifecycle,
        ProfileRegistry,
        RoutePolicy,
        Validator
      }

      alias SymphonyElixir.Workflow.Profile.Options, as: ProfileOptions

      @profile unquote(profile)

      test "profile identity is registered and resolvable" do
        assert {:ok, @profile} == ProfileRegistry.fetch(@profile.kind(), @profile.version())

        assert {:ok, resolved_profile} =
                 ProfileRegistry.resolve(%{
                   "kind" => @profile.kind(),
                   "version" => @profile.version(),
                   "options" => @profile.default_options()
                 })

        assert resolved_profile.kind == @profile.kind()
        assert resolved_profile.version == @profile.version()
        assert resolved_profile.module == @profile
      end

      test "route maps cover the complete profile route vocabulary" do
        route_keys = @profile.route_keys()
        policy_by_route_key = @profile.default_policy_by_route_key(@profile.default_options())
        lifecycle_phase_by_route_key = @profile.lifecycle_phase_by_route_key()

        assert [_ | _] = route_keys
        assert Enum.all?(route_keys, &is_atom/1)
        assert Enum.uniq(route_keys) == route_keys

        assert MapSet.new(Map.keys(policy_by_route_key)) == MapSet.new(route_keys)
        assert MapSet.new(Map.keys(lifecycle_phase_by_route_key)) == MapSet.new(route_keys)

        assert Enum.all?(Map.values(lifecycle_phase_by_route_key), &Lifecycle.valid_phase?/1)
      end

      test "default route policies are valid for the profile" do
        profile_context = resolved_default_profile_context()
        route_keys = @profile.route_keys()
        policy_by_route_key = @profile.default_policy_by_route_key(@profile.default_options())
        allowed_execution_profiles = ExecutionProfileRegistry.effective_allowed_execution_profiles(profile_context)

        assert is_map(@profile.default_policy_by_route_key())

        Enum.each(policy_by_route_key, fn {route_key, policy} ->
          assert route_key in route_keys
          assert RoutePolicy.valid_action?(Map.get(policy, :action))

          if RoutePolicy.transition_action?(Map.get(policy, :action)) do
            transition_target = Map.get(policy, :transition_target)

            assert transition_target in route_keys
            refute transition_target == route_key
          end

          if Map.has_key?(policy, :execution_profile) do
            assert Map.get(policy, :action) == :dispatch
            assert Map.get(policy, :execution_profile) in allowed_execution_profiles
          end
        end)
      end

      test "completion contract is valid and route-scoped" do
        assert :ok == ProfileRegistry.validate_completion_contract(@profile, @profile.default_options())

        contract = @profile.completion_contract(@profile.default_options())
        allowed_completion_routes = Map.fetch!(contract, :allowed_completion_routes)

        assert [_ | _] = allowed_completion_routes
        assert Enum.all?(allowed_completion_routes, &RoutePolicy.route_key?(&1, @profile))
      end

      test "capability and execution profile declarations are well formed" do
        options = @profile.default_options()

        required_capabilities = @profile.required_capabilities(options)
        optional_capabilities = @profile.optional_capabilities(options)
        allowed_execution_profiles = @profile.allowed_execution_profiles(options)

        assert non_empty_string_list?(required_capabilities)
        assert string_list?(optional_capabilities)
        assert string_list?(allowed_execution_profiles)
        assert Enum.uniq(required_capabilities) == required_capabilities
        assert Enum.uniq(optional_capabilities) == optional_capabilities
        assert Enum.uniq(allowed_execution_profiles) == allowed_execution_profiles

        Enum.each(allowed_execution_profiles, fn execution_profile ->
          assert string_list?(@profile.execution_profile_required_capabilities(execution_profile, options))
        end)
      end

      test "profile option schema drives defaults and validates default options" do
        assert is_map(@profile.options_schema())
        assert @profile.default_options() == ProfileOptions.default_options(@profile.options_schema())
        assert :ok == @profile.validate_options(@profile.default_options())
      end

      test "default effective workflow passes tracker-agnostic workflow validation" do
        assert :ok == Validator.validate_workflow(:profile_contract, default_effective_workflow())
      end

      test "unknown profile options fail fast" do
        unknown_options = Map.put(@profile.default_options(), "__unknown_profile_option__", true)

        assert {:error, {:unknown_profile_option, kind, "__unknown_profile_option__"}} =
                 @profile.validate_options(unknown_options)

        assert kind == @profile.kind()
      end

      defp default_effective_workflow do
        options = @profile.default_options()
        raw_state_by_route_key = RoutePolicy.identity_raw_state_by_route_key(@profile)
        policy_by_route_key = @profile.default_policy_by_route_key(options)
        lifecycle_phase_by_route_key = @profile.lifecycle_phase_by_route_key()

        state_phase_map =
          Map.new(raw_state_by_route_key, fn {route_key, raw_state} ->
            {raw_state, Map.fetch!(lifecycle_phase_by_route_key, route_key)}
          end)

        active_states =
          policy_by_route_key
          |> Enum.flat_map(fn {route_key, policy} ->
            if Map.get(policy, :action) in [:dispatch, :transition, :transition_then_dispatch] do
              [Map.fetch!(raw_state_by_route_key, route_key)]
            else
              []
            end
          end)

        terminal_states =
          lifecycle_phase_by_route_key
          |> Enum.flat_map(fn {route_key, phase} ->
            if phase in ["done", "canceled"] do
              [Map.fetch!(raw_state_by_route_key, route_key)]
            else
              []
            end
          end)

        %{
          profile: %{
            "kind" => @profile.kind(),
            "version" => @profile.version(),
            "options" => options
          },
          active_states: active_states,
          terminal_states: terminal_states,
          state_phase_map: state_phase_map,
          raw_state_by_route_key: raw_state_by_route_key,
          policy_by_route_key: policy_by_route_key
        }
      end

      defp resolved_default_profile_context do
        @profile
        |> default_profile_config()
        |> ProfileRegistry.resolve()
        |> case do
          {:ok, resolved_profile} -> resolved_profile
        end
      end

      defp default_profile_config(profile) do
        %{
          "kind" => profile.kind(),
          "version" => profile.version(),
          "options" => profile.default_options()
        }
      end

      defp non_empty_string_list?(values) when is_list(values) and values != [] do
        Enum.all?(values, &non_empty_string?/1)
      end

      defp non_empty_string_list?(_values), do: false

      defp string_list?(values) when is_list(values), do: Enum.all?(values, &non_empty_string?/1)
      defp string_list?(_values), do: false

      defp non_empty_string?(value) when is_binary(value), do: String.trim(value) != ""
      defp non_empty_string?(_value), do: false
    end
  end
end
