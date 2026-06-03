defmodule SymphonyElixir.WorkflowRouteMapBoundaryTest do
  use ExUnit.Case, async: true

  @route_policy_file "lib/symphony_elixir/workflow/route_policy.ex"

  @issue_workflow_runtime_files [
    "lib/symphony_elixir/workflow/capabilities.ex",
    "lib/symphony_elixir/workflow/readiness/facts.ex"
  ]

  @raw_resolver_names [
    "resolve_policy_by_route_key",
    "resolve_raw_state_by_route_key"
  ]

  test "effective route-map lookup helpers do not fall back to raw string route keys" do
    source = read_source(@route_policy_file)

    for {function, start_marker, end_marker} <- [
          {"raw_state_for_route_key/2", "  def raw_state_for_route_key", "  @spec policy_for_route_key"},
          {"policy_for_route_key/2", "  def policy_for_route_key", "  @spec disabled_route?"},
          {"disabled_route?/2", "  def disabled_route?", "  @spec remove_disabled_raw_states"}
        ] do
      body = source_slice(source, start_marker, end_marker)

      refute body =~ "Atom.to_string",
             "#{function} must not translate effective route atoms back to raw string keys"

      refute Regex.match?(~r/Map\.get\([^\n]+Atom\.to_string/s, body),
             "#{function} must not use string-key fallback for route-map lookup"
    end
  end

  test "issue workflow effective facts are not passed through raw route-map resolvers" do
    for file <- @issue_workflow_runtime_files do
      source = read_source(file)

      for resolver_name <- @raw_resolver_names do
        refute raw_resolver_receives_issue_workflow?(source, resolver_name),
               "#{file} must not pass issue.workflow facts to #{resolver_name}/..."
      end
    end
  end

  defp raw_resolver_receives_issue_workflow?(source, resolver_name) do
    direct_call_pattern =
      Regex.compile!("(?:RoutePolicy\\.)?#{resolver_name}\\([^)]*issue_workflow", "s")

    pipe_pattern =
      Regex.compile!("issue_workflow\\s*\\|>[\\s\\S]{0,400}?#{resolver_name}")

    Regex.match?(direct_call_pattern, source) or Regex.match?(pipe_pattern, source)
  end

  defp read_source(relative_path) do
    relative_path
    |> Path.expand(File.cwd!())
    |> File.read!()
  end

  defp source_slice(source, start_marker, end_marker) do
    start_index = marker_index!(source, start_marker)
    end_index = marker_index!(source, end_marker)
    binary_part(source, start_index, end_index - start_index)
  end

  defp marker_index!(source, marker) do
    case :binary.match(source, marker) do
      {index, _length} -> index
      :nomatch -> flunk("missing source marker #{inspect(marker)}")
    end
  end
end
