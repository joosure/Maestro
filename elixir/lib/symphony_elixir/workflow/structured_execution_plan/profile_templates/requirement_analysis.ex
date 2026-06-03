defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProfileTemplates.RequirementAnalysis do
  @moduledoc """
  Pure structured execution plan template for `requirement_analysis.v1`.

  This module only builds a backend-owned canonical plan record. It does not
  create Store records, expose tools, render Workpads, or participate in
  readiness policy.
  """

  alias SymphonyElixir.Workflow.Profiles.RequirementAnalysis, as: Profile
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Schema

  @profile %{"kind" => "requirement_analysis", "version" => 1}
  @extension_key "symphony.requirement_analysis"

  @required_attrs ~w(plan_id run_id issue_id tracker_kind created_at)
  @optional_attrs ~w(issue_identifier route_key status updated_at)
  @allowed_attrs @required_attrs ++ @optional_attrs

  @default_route_key "analyzing"
  @default_status "active"
  @template_statuses ~w(draft active)
  @allowed_completion_routes ~w(needs_info review ready rejected)
  @agent_owned_item_kinds ~w(agent_step)

  @item_specs [
    %{
      "item_id" => "analysis.ambiguities",
      "title" => "Record ambiguity list",
      "kind" => "agent_step",
      "required" => true,
      "criticality" => "profile_required",
      "owned_by" => "agent",
      "depends_on" => [],
      "evidence_requirements" => [
        %{
          "evidence_kind" => "requirement_analysis.ambiguities_recorded",
          "required_fields" => ["ambiguities"],
          "trust_classes" => ["agent_declared"]
        }
      ],
      "extensions" => %{
        "symphony.requirement_analysis" => %{
          "completion_contract" => "required_outputs.ambiguity_list"
        }
      }
    },
    %{
      "item_id" => "analysis.assumptions",
      "title" => "Separate assumptions from facts",
      "kind" => "agent_step",
      "required" => true,
      "criticality" => "profile_required",
      "owned_by" => "agent",
      "depends_on" => [],
      "evidence_requirements" => [
        %{
          "evidence_kind" => "requirement_analysis.assumptions_recorded",
          "required_fields" => ["assumptions", "facts"],
          "trust_classes" => ["agent_declared"]
        }
      ],
      "extensions" => %{
        "symphony.requirement_analysis" => %{
          "completion_contract" => "required_outputs.assumptions_vs_facts"
        }
      }
    },
    %{
      "item_id" => "analysis.questions",
      "title" => "Classify open questions",
      "kind" => "agent_step",
      "required" => true,
      "criticality" => "profile_required",
      "owned_by" => "agent",
      "depends_on" => [],
      "evidence_requirements" => [
        %{
          "evidence_kind" => "requirement_analysis.questions_classified",
          "required_fields" => ["blocking_questions", "non_blocking_questions"],
          "trust_classes" => ["agent_declared"]
        }
      ],
      "extensions" => %{
        "symphony.requirement_analysis" => %{
          "completion_contract" => "required_outputs.open_questions"
        }
      }
    },
    %{
      "item_id" => "analysis.acceptance_criteria",
      "title" => "Draft acceptance criteria when enough information exists",
      "kind" => "agent_step",
      "required" => false,
      "criticality" => "informational",
      "owned_by" => "agent",
      "depends_on" => ["analysis.ambiguities", "analysis.assumptions", "analysis.questions"],
      "evidence_requirements" => [
        %{
          "evidence_kind" => "requirement_analysis.acceptance_criteria_drafted",
          "required_fields" => ["acceptance_criteria"],
          "trust_classes" => ["agent_declared"]
        }
      ],
      "extensions" => %{
        "symphony.requirement_analysis" => %{
          "completion_contract" => "conditional_evidence.acceptance_criteria"
        }
      }
    },
    %{
      "item_id" => "analysis.source_references",
      "title" => "Record source references when present",
      "kind" => "agent_step",
      "required" => false,
      "criticality" => "informational",
      "owned_by" => "agent",
      "depends_on" => ["analysis.ambiguities", "analysis.assumptions", "analysis.questions"],
      "evidence_requirements" => [
        %{
          "evidence_kind" => "requirement_analysis.source_references_recorded",
          "required_fields" => ["references"],
          "trust_classes" => ["agent_declared"]
        }
      ],
      "extensions" => %{
        "symphony.requirement_analysis" => %{
          "completion_contract" => "conditional_evidence.source_references"
        }
      }
    },
    %{
      "item_id" => "analysis.tracker_summary",
      "title" => "Write analysis summary for tracker audience",
      "kind" => "handoff_record",
      "required" => true,
      "criticality" => "profile_required",
      "owned_by" => "backend",
      "depends_on" => ["analysis.ambiguities", "analysis.assumptions", "analysis.questions"],
      "evidence_requirements" => [
        %{
          "evidence_kind" => "tracker_upsert_workpad",
          "required_fields" => ["tracker_kind", "workpad_id"],
          "trust_classes" => ["tool_generated"]
        }
      ],
      "extensions" => %{
        "symphony.requirement_analysis" => %{
          "completion_contract" => "handoff_expectations.tracker_summary"
        }
      }
    },
    %{
      "item_id" => "analysis.route_selection",
      "title" => "Route issue to selected completion state",
      "kind" => "state_transition",
      "required" => true,
      "criticality" => "profile_required",
      "owned_by" => "backend",
      "depends_on" => [
        "analysis.ambiguities",
        "analysis.assumptions",
        "analysis.questions",
        "analysis.tracker_summary"
      ],
      "evidence_requirements" => [
        %{
          "evidence_kind" => "tracker_move_issue",
          "required_fields" => ["route_key", "lifecycle_phase"],
          "trust_classes" => ["tool_generated"]
        }
      ],
      "extensions" => %{
        "symphony.requirement_analysis" => %{
          "completion_contract" => "handoff_expectations.route_selection"
        }
      }
    }
  ]

  @spec profile() :: map()
  def profile, do: @profile

  @spec extension_key() :: String.t()
  def extension_key, do: @extension_key

  @spec agent_owned_item_kinds() :: [String.t()]
  def agent_owned_item_kinds, do: @agent_owned_item_kinds

  @spec required_item_ids() :: [String.t()]
  def required_item_ids do
    @item_specs
    |> Enum.filter(&Map.fetch!(&1, "required"))
    |> Enum.map(&Map.fetch!(&1, "item_id"))
  end

  @spec item_ids() :: [String.t()]
  def item_ids, do: Enum.map(@item_specs, &Map.fetch!(&1, "item_id"))

  @spec evidence_mapping() :: %{String.t() => [map()]}
  def evidence_mapping do
    Map.new(@item_specs, fn spec -> {Map.fetch!(spec, "item_id"), Map.fetch!(spec, "evidence_requirements")} end)
  end

  @spec build(keyword() | map()) :: {:ok, map()} | {:error, map()}
  def build(attrs) when is_list(attrs) or is_map(attrs) do
    with {:ok, attrs} <- normalize_attrs(attrs),
         :ok <- reject_unknown_attrs(attrs),
         :ok <- require_attrs(attrs),
         {:ok, route_key} <- normalize_route_key(Map.get(attrs, "route_key", @default_route_key)),
         {:ok, status} <- normalize_status(Map.get(attrs, "status", @default_status)) do
      attrs
      |> plan(route_key, status)
      |> Schema.validate()
    end
  end

  def build(_attrs) do
    {:error,
     %{
       code: "invalid_template_attrs",
       message: "Requirement analysis structured plan template attrs must be a map or keyword list."
     }}
  end

  defp plan(attrs, route_key, status) do
    created_at = Map.fetch!(attrs, "created_at")
    updated_at = Map.get(attrs, "updated_at", created_at)

    %{
      "schema" => Contract.schema_id(),
      "plan_id" => Map.fetch!(attrs, "plan_id"),
      "run_id" => Map.fetch!(attrs, "run_id"),
      "issue_id" => Map.fetch!(attrs, "issue_id"),
      "tracker_kind" => Map.fetch!(attrs, "tracker_kind"),
      "workflow_profile" => @profile,
      "route_key" => route_key,
      "lifecycle_phase" => lifecycle_phase(route_key),
      "status" => status,
      "items" => items(created_at, updated_at),
      "created_at" => created_at,
      "updated_at" => updated_at,
      "revision" => 1,
      "extensions" => %{
        @extension_key => %{
          "adoption_stage" => "profile_template",
          "allowed_completion_routes" => @allowed_completion_routes,
          "agent_owned_item_kinds" => @agent_owned_item_kinds,
          "readiness_authority" => "none"
        }
      }
    }
    |> maybe_put("issue_identifier", Map.get(attrs, "issue_identifier"))
  end

  defp items(created_at, updated_at) do
    Enum.map(@item_specs, fn spec ->
      %{
        "item_id" => Map.fetch!(spec, "item_id"),
        "parent_item_id" => nil,
        "title" => Map.fetch!(spec, "title"),
        "kind" => Map.fetch!(spec, "kind"),
        "status" => "pending",
        "required" => Map.fetch!(spec, "required"),
        "criticality" => Map.fetch!(spec, "criticality"),
        "owned_by" => Map.fetch!(spec, "owned_by"),
        "source" => "profile",
        "depends_on" => Map.fetch!(spec, "depends_on"),
        "evidence_requirements" => Map.fetch!(spec, "evidence_requirements"),
        "evidence_refs" => [],
        "created_at" => created_at,
        "updated_at" => updated_at,
        "revision" => 1,
        "extensions" => Map.fetch!(spec, "extensions")
      }
    end)
  end

  defp normalize_attrs(attrs) do
    {:ok, Map.new(attrs, fn {key, value} -> {normalize_key(key), value} end)}
  rescue
    Protocol.UndefinedError ->
      {:error,
       %{
         code: "invalid_template_attrs",
         message: "Requirement analysis structured plan template attrs must be enumerable."
       }}
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: key

  defp reject_unknown_attrs(attrs) do
    unknown_attrs = attrs |> Map.keys() |> Enum.reject(&(&1 in @allowed_attrs))

    if unknown_attrs == [] do
      :ok
    else
      {:error,
       %{
         code: "unknown_template_attrs",
         message: "Requirement analysis structured plan template received unknown attrs.",
         fields: Enum.map(unknown_attrs, &field_name/1)
       }}
    end
  end

  defp require_attrs(attrs) do
    missing_attrs = Enum.reject(@required_attrs, &non_empty_string?(Map.get(attrs, &1)))

    if missing_attrs == [] do
      :ok
    else
      {:error,
       %{
         code: "missing_required_template_attrs",
         message: "Requirement analysis structured plan template is missing required attrs.",
         fields: missing_attrs
       }}
    end
  end

  defp normalize_route_key(route_key) when is_binary(route_key) do
    if route_key in route_keys() do
      {:ok, route_key}
    else
      {:error,
       %{
         code: "invalid_route_key",
         message: "Requirement analysis structured plan route_key is not supported.",
         route_key: route_key
       }}
    end
  end

  defp normalize_route_key(route_key) do
    {:error,
     %{
       code: "invalid_route_key",
       message: "Requirement analysis structured plan route_key must be a string.",
       route_key: route_key
     }}
  end

  defp normalize_status(status) when status in @template_statuses, do: {:ok, status}

  defp normalize_status(status) do
    {:error,
     %{
       code: "invalid_template_status",
       message: "Requirement analysis structured plan template status must be draft or active.",
       status: status
     }}
  end

  defp route_keys, do: Enum.map(Profile.route_keys(), &Atom.to_string/1)

  defp lifecycle_phase(route_key) do
    Profile.lifecycle_phase_by_route_key()
    |> Map.new(fn {key, phase} -> {Atom.to_string(key), phase} end)
    |> Map.fetch!(route_key)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp field_name(value) when is_binary(value), do: value
  defp field_name(value), do: inspect(value)
end
