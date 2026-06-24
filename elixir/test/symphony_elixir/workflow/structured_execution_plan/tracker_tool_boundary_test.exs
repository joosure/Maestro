defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.TrackerToolBoundaryTest do
  use ExUnit.Case, async: true

  @structured_plan_core_dir Path.expand("../../../../lib/symphony_elixir/workflow/structured_execution_plan", __DIR__)
  @tool_executor_file Path.join(@structured_plan_core_dir, "tool_executor.ex")

  @provider_specific_names ~w(linear tapd github cnb jira gitlab)
  @provider_specific_tool_prefixes Enum.map(@provider_specific_names, &(&1 <> "_"))

  @alias_boundary_files [
    Path.join(@structured_plan_core_dir, "dynamic_tool_source.ex"),
    Path.join(@structured_plan_core_dir, "tool/aliases.ex"),
    Path.join(@structured_plan_core_dir, "dynamic_tool_source/provider_context.ex")
  ]

  test "structured plan core does not bind evidence to concrete tracker tool names" do
    for {path, source} <- core_sources_except(@alias_boundary_files),
        prefix <- @provider_specific_tool_prefixes do
      refute source =~ prefix,
             "#{Path.relative_to_cwd(path)} references provider-facing tool prefix #{inspect(prefix)}; " <>
               "normalize provider/tracker aliases at DynamicToolSource or adapter boundaries"
    end
  end

  test "structured plan core does not branch on concrete provider or tracker names" do
    for {path, source} <- core_sources_except(@alias_boundary_files),
        provider <- @provider_specific_names do
      refute Regex.match?(word_pattern(provider), source),
             "#{Path.relative_to_cwd(path)} references concrete provider/tracker #{inspect(provider)}"
    end
  end

  test "canonical tool executor does not consume provider-facing alias registry" do
    source = File.read!(@tool_executor_file)

    refute source =~ "Tool.Aliases"
    refute source =~ "canonical_name"
    refute source =~ "provider_alias_specs"
  end

  defp structured_plan_core_sources do
    @structured_plan_core_dir
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.map(&{&1, File.read!(&1)})
  end

  defp core_sources_except(excluded_paths) do
    excluded = MapSet.new(Enum.map(excluded_paths, &Path.expand/1))

    structured_plan_core_sources()
    |> Enum.reject(fn {path, _source} -> MapSet.member?(excluded, Path.expand(path)) end)
  end

  defp word_pattern(value), do: ~r/(^|[^A-Za-z0-9_])#{Regex.escape(value)}([^A-Za-z0-9_]|$)/
end
