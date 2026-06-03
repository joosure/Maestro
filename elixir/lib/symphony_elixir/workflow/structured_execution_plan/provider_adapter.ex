defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter do
  @moduledoc """
  Gated facade for provider-native plan/todo/task adapter behavior.

  The facade records provider-native session events only as non-authoritative
  proposals or display metadata. It is not wired into default agent, MCP, or
  Dynamic Tool paths.
  """

  alias SymphonyElixir.Agent.DynamicTool.Serializer
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ToolExecutor

  @provider_adapters_gate "workflow.structured_execution_plan.provider_adapters.enabled"
  @missing_limit 20

  @spec gate_key() :: String.t()
  def gate_key, do: @provider_adapters_gate

  @spec normalize_event(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def normalize_event(event, opts \\ []) when is_list(opts) do
    case ensure_gate(opts) do
      :ok -> ProviderSessionEvent.normalize(event, opts)
      {:skip, result} -> {:ok, result}
    end
  end

  @spec ingest_event(String.t(), map(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def ingest_event(plan_id, event, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_map(event) and is_integer(expected_revision) and is_list(opts) do
    case ensure_gate(opts) do
      :ok ->
        with {:ok, normalized_event} <- ProviderSessionEvent.normalize(event, opts),
             {:ok, updated_plan} <- Store.record_provider_session_event(plan_id, normalized_event, expected_revision, store_opts(opts)) do
          {:ok,
           %{
             "success" => true,
             "status" => "recorded",
             "plan_id" => plan_id,
             "plan_revision" => Map.get(updated_plan, "revision"),
             "provider_session_event" => normalized_event
           }}
        end

      {:skip, result} ->
        {:ok, result}
    end
  end

  @spec task_completed_guard(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def task_completed_guard(plan_id, opts \\ []) when is_binary(plan_id) and is_list(opts) do
    case ensure_gate(opts) do
      :ok ->
        with {:ok, plan} <- Store.fetch(plan_id, store_opts(opts)), do: guard_plan(plan)

      {:skip, result} ->
        {:ok, result}
    end
  end

  @spec execute_mcp_tool(String.t() | nil, term(), keyword()) :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def execute_mcp_tool(tool, arguments, opts \\ []) when is_list(opts) do
    case ensure_gate(opts) do
      :ok -> ToolExecutor.execute(tool, arguments, opts)
      {:skip, _result} -> typed_failure("provider_adapters_gate_disabled", "Structured plan provider adapters are disabled.", %{"gate" => @provider_adapters_gate})
    end
  end

  defp ensure_gate(opts) do
    if gate_enabled?(opts) do
      :ok
    else
      {:skip,
       %{
         "success" => true,
         "status" => "skipped",
         "reason" => "provider_adapters_gate_disabled",
         "gate" => @provider_adapters_gate,
         "plan_changed" => false
       }}
    end
  end

  defp gate_enabled?(opts) do
    gates = Keyword.get(opts, :gates, Contract.gate_defaults())
    config = Keyword.get(opts, :structured_execution_plan, %{})

    gate_value(gates, @provider_adapters_gate) == true or
      option_value(config, @provider_adapters_gate) == true or
      option_value(config, :provider_adapters_enabled) == true
  end

  defp gate_value(gates, gate_key) when is_map(gates), do: Map.get(gates, gate_key)
  defp gate_value(_gates, _gate_key), do: nil

  defp option_value(map, key) when is_map(map) and is_atom(key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp option_value(map, key) when is_map(map) and is_binary(key), do: Map.get(map, key)
  defp option_value(_map, _key), do: nil

  defp guard_plan(plan) when is_map(plan) do
    missing_items = missing_evidence_items(plan)

    if missing_items == [] do
      {:ok, %{"success" => true, "status" => "passed", "missing_items" => []}}
    else
      {:error,
       %{
         code: "structured_plan_missing_required_evidence",
         message: "Provider-native task completion cannot satisfy structured plan evidence requirements.",
         status: "blocked",
         missing_items: missing_items
       }}
    end
  end

  defp missing_evidence_items(plan) do
    plan
    |> Map.get("items", [])
    |> Enum.filter(&critical_evidence_bound_item?/1)
    |> Enum.reject(&Reconciler.satisfied?/1)
    |> Enum.take(@missing_limit)
    |> Enum.map(fn item ->
      %{
        "item_id" => Map.get(item, "item_id"),
        "status" => Map.get(item, "status"),
        "evidence_kinds" => item |> Map.get("evidence_requirements", []) |> Enum.map(&Map.get(&1, "evidence_kind")) |> Enum.reject(&is_nil/1)
      }
    end)
  end

  defp critical_evidence_bound_item?(item) when is_map(item) do
    Map.get(item, "required") == true and
      Map.get(item, "criticality") in ["handoff_blocking", "profile_required"] and
      Map.get(item, "evidence_requirements", []) != []
  end

  defp critical_evidence_bound_item?(_item), do: false

  defp store_opts(opts) do
    []
    |> maybe_put(:server, Keyword.get(opts, :server) || Keyword.get(opts, :structured_execution_plan_store))
    |> maybe_put(:updated_at, Keyword.get(opts, :updated_at))
  end

  defp typed_failure(code, message, details) do
    {:failure, %{"error" => %{"code" => code, "message" => message, "details" => Serializer.json_safe_value(details)}}}
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
