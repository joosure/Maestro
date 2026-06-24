defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter.Options do
  @moduledoc """
  Boundary parser for provider adapter options.

  This module owns raw option parsing for provider adapter entrypoints. Runtime
  adapter code consumes normalized accessors instead of reading atom/string
  option keys directly.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract

  @structured_execution_plan_key :structured_execution_plan
  @structured_execution_plan_store_key :structured_execution_plan_store
  @gates_key :gates
  @server_key :server
  @server_string_key "server"
  @updated_at_key :updated_at
  @provider_gate Contract.provider_adapters_enabled_gate_key()

  @spec gate_key() :: String.t()
  def gate_key, do: @provider_gate

  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts) when is_list(opts) do
    gates = Keyword.get(opts, @gates_key, Contract.gate_defaults())
    config = structured_plan_opts(opts)

    gates_enabled?(gates) or structured_gate_enabled?(config)
  end

  @spec store_opts(keyword()) :: keyword()
  def store_opts(opts) when is_list(opts) do
    config = structured_plan_opts(opts)

    []
    |> maybe_put(:server, structured_store_server(config) || top_level_store_server(opts))
    |> maybe_put(:updated_at, Keyword.get(opts, @updated_at_key))
  end

  defp structured_plan_opts(opts), do: Keyword.get(opts, @structured_execution_plan_key, %{})

  defp gates_enabled?(gates) when is_map(gates), do: Map.get(gates, @provider_gate) == true
  defp gates_enabled?(_gates), do: false

  defp structured_gate_enabled?(config) when is_map(config), do: Map.get(config, @provider_gate) == true
  defp structured_gate_enabled?(_config), do: false

  defp structured_store_server(config) when is_map(config), do: Map.get(config, @server_key) || Map.get(config, @server_string_key)
  defp structured_store_server(_config), do: nil

  defp top_level_store_server(opts), do: Keyword.get(opts, @server_key) || Keyword.get(opts, @structured_execution_plan_store_key)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
