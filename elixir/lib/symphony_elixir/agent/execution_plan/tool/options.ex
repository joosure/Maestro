defmodule SymphonyElixir.Agent.ExecutionPlan.Tool.Options do
  @moduledoc """
  Boundary normalization for Agent execution-plan tool runtime options.

  Dynamic Tool sources may pass routing and clock options through different
  aliases. This module owns that boundary parsing so the executor only receives
  Store-ready options.
  """

  @spec source_context(keyword()) :: map()
  def source_context(opts) when is_list(opts) do
    %{}
    |> Map.put(:expose?, Keyword.get(opts, :expose?, false))
    |> maybe_put(:server, store_server(opts))
    |> maybe_put(:now, Keyword.get(opts, :now))
    |> maybe_put(:updated_at, Keyword.get(opts, :updated_at))
  end

  @spec merge_source_context(keyword(), term()) :: keyword()
  def merge_source_context(opts, source_context) when is_list(opts) and is_map(source_context) do
    opts
    |> maybe_put(:server, context_value(source_context, :server, "server"))
    |> maybe_put(:now, context_value(source_context, :now, "now"))
    |> maybe_put(:updated_at, context_value(source_context, :updated_at, "updated_at"))
  end

  def merge_source_context(opts, _source_context) when is_list(opts), do: opts

  @spec expose?(term()) :: boolean()
  def expose?(source_context) when is_map(source_context) do
    Map.get(source_context, :expose?, Map.get(source_context, "expose?", false)) == true
  end

  def expose?(_source_context), do: false

  @spec store_opts(keyword()) :: keyword()
  def store_opts(opts) when is_list(opts) do
    []
    |> maybe_put(:server, store_server(opts))
    |> maybe_put(:now, Keyword.get(opts, :now))
    |> maybe_put(:updated_at, Keyword.get(opts, :updated_at))
  end

  defp store_server(opts), do: Keyword.get(opts, :server) || Keyword.get(opts, :agent_execution_plan_store)

  defp context_value(map, atom_key, string_key), do: Map.get(map, atom_key) || Map.get(map, string_key)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value) when is_list(opts), do: Keyword.put(opts, key, value)
  defp maybe_put(map, key, value) when is_map(map), do: Map.put(map, key, value)
end
