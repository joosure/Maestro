defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceRecorder do
  @moduledoc """
  Mirrors successful typed workflow tool results into active structured plans.

  Recording is disabled by default and only runs when the caller explicitly
  enables `workflow.structured_execution_plan.enabled` through opts.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store

  @spec record_typed_tool_result(String.t() | atom() | nil, term(), String.t() | nil, term(), term(), keyword()) :: :ok
  def record_typed_tool_result(source_kind, source_context, tool, arguments, result, opts \\ []) do
    if enabled?(opts) do
      do_record_typed_tool_result(source_kind, source_context, tool, arguments, result, opts)
    else
      :ok
    end
  end

  defp do_record_typed_tool_result(source_kind, source_context, tool, arguments, result, opts) do
    with {:ok, evidence_refs} <- EvidenceBinding.bind_typed_tool_result(source_kind, source_context, tool, arguments, result, opts),
         true <- evidence_refs != [],
         {:ok, plan_id} <- resolve_plan_id(opts) do
      _result = Store.record_evidence_refs(plan_id, evidence_refs, store_opts(opts))
      :ok
    else
      false -> :ok
      _error -> :ok
    end
  end

  defp enabled?(opts) do
    case structured_plan_opts(opts) do
      %{enabled: true} -> true
      %{"enabled" => true} -> true
      keyword when is_list(keyword) -> Keyword.get(keyword, :enabled, false) == true
      _config -> Keyword.get(opts, :structured_execution_plan_enabled?, false) == true
    end
  end

  defp resolve_plan_id(opts) do
    config = structured_plan_opts(opts)

    cond do
      plan_id = option_value(config, :plan_id) ->
        {:ok, plan_id}

      true ->
        resolve_active_plan_id(config, opts)
    end
  end

  defp resolve_active_plan_id(config, opts) do
    with run_id when is_binary(run_id) <- option_value(config, :run_id) || runtime_value(opts, :run_id),
         workflow_profile when is_map(workflow_profile) <- option_value(config, :workflow_profile),
         route_key when is_binary(route_key) <- option_value(config, :route_key),
         {:ok, %{"plan_id" => plan_id}} <- Store.active_plan(run_id, workflow_profile, route_key, store_opts(opts)) do
      {:ok, plan_id}
    else
      _error -> {:error, %{code: "plan_not_found", message: "Structured execution plan was not found."}}
    end
  end

  defp runtime_value(opts, key) do
    runtime_metadata =
      case Keyword.get(opts, :tool_context) do
        %{runtime_metadata: metadata} when is_map(metadata) -> metadata
        %{"runtime_metadata" => metadata} when is_map(metadata) -> metadata
        _context -> %{}
      end

    Keyword.get(opts, key) || Map.get(runtime_metadata, key) || Map.get(runtime_metadata, Atom.to_string(key))
  end

  defp store_opts(opts) do
    config = structured_plan_opts(opts)

    []
    |> maybe_put(:server, option_value(config, :server) || Keyword.get(opts, :structured_execution_plan_store))
    |> maybe_put(:updated_at, Keyword.get(opts, :updated_at))
  end

  defp structured_plan_opts(opts), do: Keyword.get(opts, :structured_execution_plan, %{})

  defp option_value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp option_value(keyword, key) when is_list(keyword), do: Keyword.get(keyword, key)
  defp option_value(_config, _key), do: nil

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
