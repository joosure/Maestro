defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ToolExecutor do
  @moduledoc """
  Executes internal structured execution plan typed tools.

  These tools are intentionally not wired into the default Dynamic Tool source.
  They provide a stable internal executor for Phase 3 tests and local smoke
  harnesses only.
  """

  alias SymphonyElixir.Agent.DynamicTool.{MetadataContract, Serializer}
  alias SymphonyElixir.Workflow.CapabilityNames
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.WorkpadRenderer

  @schema_version "1"
  @source_kind "workflow"
  @max_summary_items 100

  @metadata_schema_version_key MetadataContract.schema_version()
  @metadata_side_effect_key MetadataContract.side_effect()
  @metadata_risk_flags_key MetadataContract.risk_flags()
  @metadata_workflow_capability_key MetadataContract.workflow_capability()
  @metadata_source_kind_key MetadataContract.source_kind()
  @metadata_operator_only_key MetadataContract.operator_only()

  @snapshot_tool "workflow_plan_snapshot"
  @upsert_tool "workflow_plan_upsert"
  @update_item_tool "workflow_plan_update_item"
  @render_workpad_tool "workflow_plan_render_workpad"

  @snapshot_capability CapabilityNames.workflow_plan_snapshot()
  @upsert_capability CapabilityNames.workflow_plan_upsert()
  @update_item_capability CapabilityNames.workflow_plan_update_item()
  @render_workpad_capability CapabilityNames.workflow_plan_render_workpad()

  @canonical_tools %{
    @snapshot_tool => @snapshot_tool,
    @upsert_tool => @upsert_tool,
    @update_item_tool => @update_item_tool,
    @render_workpad_tool => @render_workpad_tool,
    "linear_plan_snapshot" => @snapshot_tool,
    "linear_plan_upsert" => @upsert_tool,
    "linear_plan_update_item" => @update_item_tool,
    "linear_plan_render_workpad" => @render_workpad_tool,
    "tapd_plan_snapshot" => @snapshot_tool,
    "tapd_plan_upsert" => @upsert_tool,
    "tapd_plan_update_item" => @update_item_tool,
    "tapd_plan_render_workpad" => @render_workpad_tool
  }

  @spec tool_specs(keyword()) :: [map()]
  def tool_specs(opts \\ []) when is_list(opts) do
    canonical_specs = [
      snapshot_spec(@snapshot_tool),
      upsert_spec(@upsert_tool),
      update_item_spec(@update_item_tool),
      render_workpad_spec(@render_workpad_tool)
    ]

    provider_alias_specs =
      opts
      |> Keyword.get(:provider_aliases, [])
      |> List.wrap()
      |> Enum.flat_map(&provider_alias_specs/1)

    canonical_specs ++ provider_alias_specs
  end

  @spec supported_tool_names(keyword()) :: [String.t()]
  def supported_tool_names(opts \\ []) when is_list(opts), do: Enum.map(tool_specs(opts), &Map.fetch!(&1, "name"))

  @spec execute(String.t() | nil, term(), keyword()) :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def execute(tool, arguments, opts \\ [])

  def execute(tool, arguments, opts) when is_binary(tool) and is_list(opts) do
    case Map.get(@canonical_tools, tool) do
      @snapshot_tool -> plan_snapshot(arguments, opts)
      @upsert_tool -> plan_upsert(arguments, opts)
      @update_item_tool -> plan_update_item(arguments, opts)
      @render_workpad_tool -> plan_render_workpad(arguments, opts)
      _tool -> typed_failure({:unsupported_tool, tool})
    end
  end

  def execute(_tool, _arguments, _opts), do: typed_failure({:unsupported_tool, nil})

  defp provider_alias_specs("linear") do
    [
      snapshot_spec("linear_plan_snapshot"),
      upsert_spec("linear_plan_upsert"),
      update_item_spec("linear_plan_update_item"),
      render_workpad_spec("linear_plan_render_workpad")
    ]
  end

  defp provider_alias_specs("tapd") do
    [
      snapshot_spec("tapd_plan_snapshot"),
      upsert_spec("tapd_plan_upsert"),
      update_item_spec("tapd_plan_update_item"),
      render_workpad_spec("tapd_plan_render_workpad")
    ]
  end

  defp provider_alias_specs(_provider), do: []

  defp snapshot_spec(name) do
    tool_spec(
      name,
      @snapshot_capability,
      "Read a bounded canonical structured execution plan summary.",
      "read_only",
      [],
      %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "plan_id" => %{"type" => ["string", "null"], "description" => "Structured plan id."},
          "run_id" => %{"type" => ["string", "null"], "description" => "Run id used with workflow_profile and route_key."},
          "workflow_profile" => %{"type" => ["object", "null"], "description" => "Workflow profile identity."},
          "route_key" => %{"type" => ["string", "null"], "description" => "Workflow route key."}
        }
      }
    )
  end

  defp upsert_spec(name) do
    tool_spec(
      name,
      @upsert_capability,
      "Create a canonical plan or merge agent-owned informational items into an existing plan.",
      "write",
      ["workflow_state_write"],
      %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "plan" => %{"type" => ["object", "null"], "description" => "Full canonical plan record for creation."},
          "plan_id" => %{"type" => ["string", "null"], "description" => "Existing structured plan id."},
          "plan_revision" => %{"type" => ["integer", "null"], "description" => "Caller-observed plan revision for item merge."},
          "items" => %{"type" => ["array", "null"], "items" => %{"type" => "object"}, "description" => "Agent-owned informational items."}
        }
      }
    )
  end

  defp update_item_spec(name) do
    tool_spec(
      name,
      @update_item_capability,
      "Request a structured plan item status update with optimistic concurrency.",
      "write",
      ["workflow_state_write"],
      %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["plan_id", "item_id", "status", "plan_revision"],
        "properties" => %{
          "plan_id" => %{"type" => "string", "description" => "Structured plan id."},
          "item_id" => %{"type" => "string", "description" => "Structured plan item id."},
          "status" => %{"type" => "string", "description" => "Requested item status."},
          "plan_revision" => %{"type" => "integer", "description" => "Caller-observed plan revision."},
          "note" => %{"type" => ["string", "null"], "description" => "Optional bounded agent note."},
          "evidence_id" => %{"type" => ["string", "null"], "description" => "Optional evidence id reference."}
        }
      }
    )
  end

  defp render_workpad_spec(name) do
    tool_spec(
      name,
      @render_workpad_capability,
      "Render a preview Workpad from the canonical structured execution plan without changing authoritative plan facts.",
      "read_only",
      [],
      %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["plan_id", "plan_revision", "mode"],
        "properties" => %{
          "plan_id" => %{"type" => "string", "description" => "Structured plan id."},
          "plan_revision" => %{"type" => "integer", "description" => "Caller-observed plan revision."},
          "mode" => %{"type" => "string", "enum" => ["preview"], "description" => "Render mode. Only preview is enabled in this phase."},
          "heading" => %{"type" => ["string", "null"], "description" => "Optional Workpad heading override."},
          "max_items" => %{"type" => ["integer", "null"], "description" => "Optional bounded item limit for preview rendering."}
        }
      }
    )
  end

  defp tool_spec(name, capability, description, side_effect, risk_flags, input_schema) do
    %{
      "name" => name,
      "description" => description,
      "inputSchema" => input_schema,
      @metadata_schema_version_key => @schema_version,
      @metadata_side_effect_key => side_effect,
      @metadata_risk_flags_key => risk_flags,
      @metadata_workflow_capability_key => capability,
      @metadata_source_kind_key => @source_kind,
      @metadata_operator_only_key => true
    }
  end

  defp plan_snapshot(arguments, opts) do
    with {:ok, args} <- snapshot_args(arguments),
         {:ok, plan} <- fetch_plan(args, opts) do
      {:success, success_payload(success_result(plan, []))}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp plan_upsert(arguments, opts) do
    case upsert_args(arguments) do
      {:ok, {:create, plan}} ->
        case Store.create(plan, store_opts(opts)) do
          {:ok, created_plan} ->
            {:success, success_payload(success_result(created_plan, Map.get(created_plan, "items", [])))}

          {:error, reason} ->
            typed_failure(reason)
        end

      {:ok, {:merge_items, plan_id, plan_revision, items}} ->
        with {:ok, before_plan} <- Store.fetch(plan_id, store_opts(opts)),
             {:ok, updated_plan} <- Store.upsert_agent_items(plan_id, items, plan_revision, store_opts(opts)) do
          changed_items = changed_items(before_plan, updated_plan)
          {:success, success_payload(success_result(updated_plan, changed_items))}
        else
          {:error, reason} -> typed_failure(reason)
        end

      {:error, reason} ->
        typed_failure(reason)
    end
  end

  defp plan_update_item(arguments, opts) do
    with {:ok, args} <- update_item_args(arguments),
         {:ok, plan} <- Store.fetch(args.plan_id, store_opts(opts)),
         :ok <- ensure_revision(plan, args.plan_revision),
         {:ok, item} <- fetch_item(plan, args.item_id),
         :ok <- ensure_completion_allowed(item, args.status),
         {:ok, updated_plan} <- Store.update_item_status(args.plan_id, args.item_id, args.status, args.plan_revision, store_opts(opts)),
         {:ok, updated_item} <- fetch_item(updated_plan, args.item_id) do
      {:success, success_payload(success_result(updated_plan, [updated_item]))}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp plan_render_workpad(arguments, opts) do
    with {:ok, args} <- render_workpad_args(arguments),
         :ok <- ensure_preview_render_mode(args.mode),
         {:ok, plan} <- Store.fetch(args.plan_id, store_opts(opts)),
         :ok <- ensure_revision(plan, args.plan_revision),
         {:ok, rendered_workpad} <- WorkpadRenderer.render(plan, render_opts(args)) do
      {:success, success_payload(success_result(plan, []) |> Map.put("rendered_workpad", rendered_workpad))}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp snapshot_args(arguments) when is_map(arguments) do
    with :ok <- reject_unknown_fields(arguments, ~w(plan_id run_id workflow_profile route_key)) do
      plan_id = optional_string(arguments, "plan_id")
      run_id = optional_string(arguments, "run_id")
      workflow_profile = Map.get(arguments, "workflow_profile")
      route_key = optional_string(arguments, "route_key")

      cond do
        is_binary(plan_id) ->
          {:ok, %{plan_id: plan_id}}

        is_binary(run_id) and is_map(workflow_profile) and is_binary(route_key) ->
          {:ok, %{run_id: run_id, workflow_profile: workflow_profile, route_key: route_key}}

        true ->
          {:error, {:invalid_arguments, "Plan snapshot requires plan_id or run_id, workflow_profile, and route_key."}}
      end
    end
  end

  defp snapshot_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object for plan snapshot."}}

  defp upsert_args(arguments) when is_map(arguments) do
    with :ok <- reject_unknown_fields(arguments, ~w(plan plan_id plan_revision items)) do
      cond do
        is_map(Map.get(arguments, "plan")) ->
          {:ok, {:create, Map.fetch!(arguments, "plan")}}

        true ->
          with {:ok, plan_id} <- required_string(arguments, "plan_id"),
               {:ok, plan_revision} <- required_positive_integer(arguments, "plan_revision"),
               {:ok, items} <- required_item_list(arguments, "items") do
            {:ok, {:merge_items, plan_id, plan_revision, items}}
          end
      end
    end
  end

  defp upsert_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object for plan upsert."}}

  defp update_item_args(arguments) when is_map(arguments) do
    with :ok <- reject_unknown_fields(arguments, ~w(plan_id item_id status plan_revision note evidence_id)),
         {:ok, plan_id} <- required_string(arguments, "plan_id"),
         {:ok, item_id} <- required_string(arguments, "item_id"),
         {:ok, status} <- required_string(arguments, "status"),
         {:ok, plan_revision} <- required_positive_integer(arguments, "plan_revision") do
      {:ok, %{plan_id: plan_id, item_id: item_id, status: status, plan_revision: plan_revision}}
    end
  end

  defp update_item_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object for plan item update."}}

  defp render_workpad_args(arguments) when is_map(arguments) do
    with :ok <- reject_unknown_fields(arguments, ~w(plan_id plan_revision mode heading max_items)),
         {:ok, plan_id} <- required_string(arguments, "plan_id"),
         {:ok, plan_revision} <- required_positive_integer(arguments, "plan_revision"),
         {:ok, mode} <- required_string(arguments, "mode"),
         {:ok, max_items} <- optional_positive_integer(arguments, "max_items") do
      {:ok,
       %{
         plan_id: plan_id,
         plan_revision: plan_revision,
         mode: mode,
         heading: optional_string(arguments, "heading"),
         max_items: max_items
       }}
    end
  end

  defp render_workpad_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object for plan Workpad rendering."}}

  defp fetch_plan(%{plan_id: plan_id}, opts), do: Store.fetch(plan_id, store_opts(opts))

  defp fetch_plan(%{run_id: run_id, workflow_profile: workflow_profile, route_key: route_key}, opts),
    do: Store.active_plan(run_id, workflow_profile, route_key, store_opts(opts))

  defp ensure_revision(%{"revision" => revision}, revision), do: :ok

  defp ensure_revision(%{"revision" => revision}, expected_revision) do
    {:error,
     %{
       code: "revision_conflict",
       message: "Structured execution plan revision does not match the caller-observed revision.",
       current_revision: revision,
       expected_revision: expected_revision
     }}
  end

  defp fetch_item(%{"items" => items}, item_id) when is_list(items) do
    case Enum.find(items, &(Map.get(&1, "item_id") == item_id)) do
      nil ->
        {:error,
         %{
           code: "item_not_found",
           message: "Structured execution plan item was not found.",
           item_id: item_id
         }}

      item ->
        {:ok, item}
    end
  end

  defp fetch_item(_plan, item_id) do
    {:error,
     %{
       code: "item_not_found",
       message: "Structured execution plan item was not found.",
       item_id: item_id
     }}
  end

  defp ensure_completion_allowed(item, "complete") do
    if evidence_bound_critical_item?(item) and not Reconciler.satisfied?(item) do
      {:error,
       %{
         code: "missing_required_evidence",
         message: "Evidence-bound critical items cannot be completed without satisfying evidence.",
         item_id: Map.get(item, "item_id")
       }}
    else
      :ok
    end
  end

  defp ensure_completion_allowed(_item, _status), do: :ok

  defp evidence_bound_critical_item?(item) do
    Map.get(item, "criticality") in ["handoff_blocking", "profile_required"] and
      Map.get(item, "evidence_requirements", []) != []
  end

  defp ensure_preview_render_mode("preview"), do: :ok

  defp ensure_preview_render_mode(_mode) do
    {:error, {:invalid_arguments, "Structured plan Workpad tool currently supports preview mode only."}}
  end

  defp changed_items(before_plan, updated_plan) do
    before_by_id =
      before_plan
      |> Map.get("items", [])
      |> Map.new(&{Map.get(&1, "item_id"), &1})

    updated_plan
    |> Map.get("items", [])
    |> Enum.reject(fn item -> Map.get(before_by_id, Map.get(item, "item_id")) == item end)
  end

  defp success_result(plan, changed_items) do
    %{
      "success" => true,
      "plan" => plan_summary(plan),
      "changed_items" => Enum.map(changed_items, &item_summary/1),
      "errors" => [],
      "warnings" => []
    }
  end

  defp plan_summary(plan) do
    items = Map.get(plan, "items", [])
    summary_items = Enum.take(items, @max_summary_items)

    plan
    |> Map.take(~w(schema plan_id run_id issue_id issue_identifier tracker_kind workflow_profile route_key lifecycle_phase status created_at updated_at revision))
    |> Map.put("items", Enum.map(summary_items, &item_summary/1))
    |> Map.put("item_count", length(items))
    |> Map.put("items_truncated", length(items) > @max_summary_items)
  end

  defp item_summary(item) do
    evidence_refs = Map.get(item, "evidence_refs", [])

    item
    |> Map.take(~w(item_id parent_item_id title kind status required criticality owned_by source depends_on evidence_requirements created_at updated_at revision))
    |> Map.put("evidence_ref_count", length(evidence_refs))
    |> Map.put("evidence_kinds", evidence_refs |> Enum.map(&Map.get(&1, "evidence_kind")) |> Enum.reject(&is_nil/1) |> Enum.uniq())
  end

  defp success_payload(data, warnings \\ []) do
    %{
      "data" => Serializer.json_safe_value(data),
      "warnings" => Serializer.json_safe_value(warnings)
    }
  end

  defp typed_failure(reason) do
    {code, message, details} = typed_error(reason)
    {:failure, %{"error" => %{"code" => code, "message" => message, "details" => Serializer.json_safe_value(details)}}}
  end

  defp typed_error({:invalid_arguments, message}), do: {"invalid_arguments", message, %{}}

  defp typed_error({:unsupported_tool, tool}) do
    {"unsupported_tool", "Structured execution plan tool is not supported.", %{"tool" => tool}}
  end

  defp typed_error(%{code: code, message: message} = error) do
    {to_string(code), message, Map.delete(error, :message)}
  end

  defp typed_error(reason) do
    {"structured_plan_tool_failed", "Structured execution plan tool execution failed.", %{"reason" => inspect(reason)}}
  end

  defp required_string(map, key) do
    case optional_string(map, key) do
      value when is_binary(value) -> {:ok, value}
      _value -> {:error, {:invalid_arguments, "Missing required string field #{key}."}}
    end
  end

  defp optional_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      value when is_integer(value) ->
        Integer.to_string(value)

      _value ->
        nil
    end
  end

  defp required_positive_integer(map, key) do
    case Map.get(map, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _value -> {:error, {:invalid_arguments, "#{key} must be a positive integer."}}
    end
  end

  defp optional_positive_integer(map, key) do
    case Map.get(map, key) do
      nil -> {:ok, nil}
      value when is_integer(value) and value > 0 -> {:ok, value}
      _value -> {:error, {:invalid_arguments, "#{key} must be a positive integer."}}
    end
  end

  defp required_item_list(map, key) do
    case Map.get(map, key) do
      values when is_list(values) ->
        if values != [] and Enum.all?(values, &is_map/1) do
          {:ok, values}
        else
          {:error, {:invalid_arguments, "#{key} must be a non-empty array of item objects."}}
        end

      _value ->
        {:error, {:invalid_arguments, "#{key} must be a non-empty array of item objects."}}
    end
  end

  defp reject_unknown_fields(map, allowed_fields) do
    unknown_fields = map |> Map.keys() |> Enum.reject(&(&1 in allowed_fields))

    if unknown_fields == [] do
      :ok
    else
      {:error, {:invalid_arguments, "Unsupported argument field(s): #{Enum.join(unknown_fields, ", ")}."}}
    end
  end

  defp store_opts(opts) do
    []
    |> maybe_put(:server, Keyword.get(opts, :server) || Keyword.get(opts, :structured_execution_plan_store))
    |> maybe_put(:updated_at, Keyword.get(opts, :updated_at))
  end

  defp render_opts(args) do
    []
    |> Keyword.put(:mode, args.mode)
    |> maybe_put(:heading, args.heading)
    |> maybe_put(:max_items, args.max_items)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
