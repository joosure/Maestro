defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceRecorder.Options do
  @moduledoc """
  Boundary parser for structured execution-plan evidence recorder options.

  This module is the only recorder layer that accepts atom-keyed and
  string-keyed option maps. Internal recorder modules consume the normalized
  accessors exposed here.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.RawInput
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields

  @structured_execution_plan_key :structured_execution_plan
  @structured_execution_plan_store_key :structured_execution_plan_store
  @gates_key :gates
  @tool_context_key :tool_context
  @plan_id_key :plan_id
  @server_key :server
  @run_id_key :run_id
  @workflow_profile_key :workflow_profile
  @route_key :route_key
  @updated_at_key :updated_at

  @type active_plan_scope :: %{
          run_id: String.t(),
          workflow_profile: map(),
          route_key: String.t()
        }

  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts) when is_list(opts) do
    opts
    |> Keyword.get(@gates_key, Contract.gate_defaults())
    |> gate_enabled?(Contract.enabled_gate_key())
  end

  @spec plan_id(keyword()) :: String.t() | nil
  def plan_id(opts) when is_list(opts) do
    opts
    |> structured_plan_opts()
    |> option_value(@plan_id_key)
    |> string_or_nil()
  end

  @spec active_plan_scope(keyword()) :: {:ok, active_plan_scope()} | :error
  def active_plan_scope(opts) when is_list(opts) do
    config = structured_plan_opts(opts)

    with run_id when is_binary(run_id) <- string_or_nil(option_value(config, @run_id_key) || runtime_value(opts, @run_id_key)),
         workflow_profile when is_map(workflow_profile) <- option_value(config, @workflow_profile_key),
         route_key when is_binary(route_key) <- string_or_nil(option_value(config, @route_key)) do
      {:ok, %{run_id: run_id, workflow_profile: workflow_profile, route_key: route_key}}
    else
      _value -> :error
    end
  end

  @spec store_opts(keyword()) :: keyword()
  def store_opts(opts) when is_list(opts) do
    config = structured_plan_opts(opts)

    []
    |> maybe_put(:server, option_value(config, @server_key) || Keyword.get(opts, @structured_execution_plan_store_key))
    |> maybe_put(:updated_at, Keyword.get(opts, @updated_at_key))
  end

  @spec diagnostic_fields(keyword()) :: map()
  def diagnostic_fields(opts) when is_list(opts) do
    config = structured_plan_opts(opts)
    profile = option_value(config, @workflow_profile_key)

    %{
      plan_id: plan_id(opts),
      run_id: string_or_nil(option_value(config, @run_id_key) || runtime_value(opts, @run_id_key)),
      workflow_profile: profile_kind(profile),
      workflow_profile_version: profile_version(profile),
      workflow_route_key: string_or_nil(option_value(config, @route_key))
    }
    |> drop_nil_values()
  end

  defp gate_enabled?(gates, gate_key) when is_map(gates), do: Map.get(gates, gate_key) == true
  defp gate_enabled?(_gates, _gate_key), do: false

  defp structured_plan_opts(opts), do: Keyword.get(opts, @structured_execution_plan_key, %{})

  defp runtime_value(opts, key) do
    opts
    |> Keyword.get(@tool_context_key)
    |> RawInput.runtime_metadata()
    |> RawInput.map_value(key)
    |> then(fn value -> Keyword.get(opts, key) || value end)
  end

  defp option_value(map, key) when is_map(map) and is_atom(key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp option_value(keyword, key) when is_list(keyword) and is_atom(key), do: Keyword.get(keyword, key)
  defp option_value(_config, _key), do: nil

  defp profile_kind(profile) when is_map(profile), do: string_or_nil(Map.get(profile, Fields.profile_kind()) || Map.get(profile, :kind))
  defp profile_kind(_profile), do: nil

  defp profile_version(profile) when is_map(profile), do: Map.get(profile, Fields.profile_version()) || Map.get(profile, :version)
  defp profile_version(_profile), do: nil

  defp string_or_nil(nil), do: nil

  defp string_or_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp string_or_nil(value) when is_atom(value), do: value |> Atom.to_string() |> string_or_nil()
  defp string_or_nil(_value), do: nil

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp drop_nil_values(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end
