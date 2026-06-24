defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile.Options do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile.Contract
  alias SymphonyElixir.Workflow.Profile.Options, as: WorkflowProfileOptions

  @enabled_route_option_schema %{
    type: {:map, %{Contract.enabled_option_key() => %{type: :boolean, default: true}}}
  }

  @route_options_schema Map.new(Contract.configurable_route_keys(), &{Atom.to_string(&1), @enabled_route_option_schema})

  @change_proposal_checks_options_schema %{
    Contract.mode_option_key() => %{
      type: {:enum, Contract.change_proposal_checks_modes()},
      default: Contract.change_proposal_checks_required_when_available()
    }
  }

  @review_handoff_options_schema %{
    Contract.change_proposal_checks_option_key() => %{type: {:map, @change_proposal_checks_options_schema}}
  }

  @readiness_options_schema %{
    Contract.review_handoff_option_key() => %{type: {:map, @review_handoff_options_schema}}
  }

  @schema %{
    Contract.requirements_option_key() => %{
      type:
        {:map,
         %{
           Contract.change_proposal_option_key() => %{type: :boolean, default: true},
           Contract.typed_tracker_tools_option_key() => %{type: :boolean, default: false},
           Contract.typed_repo_tools_option_key() => %{type: :boolean, default: false}
         }}
    },
    Contract.execution_profiles_option_key() => %{
      type:
        {:map,
         %{
           Contract.allowed_execution_profiles_option_key() => %{
             type: {:name_list, min: 1, unique: true},
             default: Contract.default_allowed_execution_profiles()
           }
         }}
    },
    Contract.readiness_option_key() => %{
      type: {:map, @readiness_options_schema}
    },
    Contract.routes_option_key() => %{
      type: {:map, @route_options_schema}
    }
  }

  @invalid_options_code "invalid_coding_pr_delivery_profile_options"

  @spec schema() :: WorkflowProfileOptions.schema()
  def schema, do: @schema

  @spec default() :: map()
  def default, do: WorkflowProfileOptions.default_options(@schema)

  @spec validate(term()) :: :ok | {:error, term()}
  def validate(options) when is_map(options), do: WorkflowProfileOptions.validate(Contract.kind(), options, @schema)

  def validate(options) do
    {:error,
     %{
       code: @invalid_options_code,
       message: "Coding PR Delivery profile options must be a map.",
       reason: :options_not_map,
       value_type: Diagnostics.type_name(options)
     }}
  end

  @spec default_allowed_execution_profiles() :: [String.t()]
  def default_allowed_execution_profiles, do: Contract.default_allowed_execution_profiles()

  @spec normalize(term()) :: map()
  def normalize(options) when is_map(options), do: options
  def normalize(_options), do: default()

  @spec change_proposal_required?(term()) :: boolean()
  def change_proposal_required?(options), do: requirement_enabled?(options, Contract.change_proposal_option_key())

  @spec typed_tracker_tools_required?(term()) :: boolean()
  def typed_tracker_tools_required?(options), do: requirement_enabled?(options, Contract.typed_tracker_tools_option_key())

  @spec typed_repo_tools_required?(term()) :: boolean()
  def typed_repo_tools_required?(options), do: requirement_enabled?(options, Contract.typed_repo_tools_option_key())

  @spec allowed_execution_profile_names(term()) :: [String.t()]
  def allowed_execution_profile_names(options) do
    options = normalize(options)
    execution_profiles = Map.get(options, Contract.execution_profiles_option_key(), %{})
    defaults = Map.fetch!(default(), Contract.execution_profiles_option_key())

    execution_profiles
    |> Map.get(Contract.allowed_execution_profiles_option_key(), Map.fetch!(defaults, Contract.allowed_execution_profiles_option_key()))
    |> Enum.uniq()
  end

  @spec review_handoff_change_proposal_checks_mode(term()) :: String.t()
  def review_handoff_change_proposal_checks_mode(options) do
    options = normalize(options)
    default_options = default()
    default_readiness = Map.fetch!(default_options, Contract.readiness_option_key())
    default_review_handoff = Map.fetch!(default_readiness, Contract.review_handoff_option_key())
    default_change_proposal_checks = Map.fetch!(default_review_handoff, Contract.change_proposal_checks_option_key())

    options
    |> option_map(Contract.readiness_option_key(), default_readiness)
    |> option_map(Contract.review_handoff_option_key(), default_review_handoff)
    |> option_map(Contract.change_proposal_checks_option_key(), default_change_proposal_checks)
    |> option_value(Contract.mode_option_key(), Contract.change_proposal_checks_required_when_available())
  end

  @spec review_handoff_change_proposal_checks_not_required?(term()) :: boolean()
  def review_handoff_change_proposal_checks_not_required?(options),
    do: review_handoff_change_proposal_checks_mode(options) == Contract.change_proposal_checks_not_required()

  @spec route_enabled?(term(), atom()) :: boolean()
  def route_enabled?(options, route_key) when is_atom(route_key) do
    options = normalize(options)
    defaults = default()
    routes = option_map(options, Contract.routes_option_key(), Map.fetch!(defaults, Contract.routes_option_key()))

    route_options =
      routes
      |> route_options(route_key)
      |> then(fn value -> if is_map(value), do: value, else: %{} end)

    option_value(route_options, Contract.enabled_option_key(), true) == true
  end

  def route_enabled?(_options, _route_key), do: true

  defp requirement_enabled?(options, key) when is_binary(key) do
    options = normalize(options)
    requirements = Map.get(options, Contract.requirements_option_key(), %{})
    defaults = Map.fetch!(default(), Contract.requirements_option_key())

    Map.get(requirements, key, Map.fetch!(defaults, key)) == true
  end

  defp option_map(options, key, default) when is_map(options) and is_binary(key) and is_map(default) do
    case option_value(options, key, default) do
      value when is_map(value) -> value
      _value -> default
    end
  end

  defp option_value(options, key, default) when is_map(options) and is_binary(key) do
    Map.get(options, key, default)
  end

  defp route_options(routes, route_key) when is_map(routes) and is_atom(route_key) do
    Map.get(routes, Atom.to_string(route_key), %{})
  end

  defp route_options(_routes, _route_key), do: %{}
end
