defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.BoundaryTest do
  use ExUnit.Case, async: true

  @structured_plan_dir Path.expand("../../../../../lib/symphony_elixir/workflow/structured_execution_plan", __DIR__)

  test "Workpad projection code lives under the Workpad namespace" do
    refute File.exists?(Path.join(@structured_plan_dir, "workpad_rendering"))
    refute File.exists?(Path.join(@structured_plan_dir, "workpad_renderer.ex"))
    refute File.exists?(Path.join(@structured_plan_dir, "workpad_writer.ex"))

    for {path, source} <- structured_plan_sources() do
      refute source =~ "WorkpadRendering", "#{Path.relative_to_cwd(path)} references the old WorkpadRendering namespace"
      refute source =~ "StructuredExecutionPlan.Writer", "#{Path.relative_to_cwd(path)} references the old Workpad writer namespace"
    end
  end

  defp structured_plan_sources do
    @structured_plan_dir
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.map(&{&1, File.read!(&1)})
  end
end
