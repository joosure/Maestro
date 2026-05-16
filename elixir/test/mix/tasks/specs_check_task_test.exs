defmodule Mix.Tasks.Specs.CheckTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Specs.Check

  setup do
    Mix.Task.reenable("specs.check")
    :ok
  end

  test "uses the default lib path when all public functions have specs" do
    in_temp_project(fn ->
      write_module!("lib/sample.ex", """
      defmodule Sample do
        @spec ok(term()) :: term()
        def ok(arg), do: arg
      end
      """)

      output =
        capture_io(fn ->
          assert :ok = Check.run([])
        end)

      assert output =~ "specs.check: all public functions have @spec or exemption"
    end)
  end

  test "raises when an explicit path contains missing specs" do
    in_temp_project(fn ->
      write_module!("src/sample.ex", """
      defmodule Sample do
        def missing(arg), do: arg
      end
      """)

      error_output =
        capture_io(:stderr, fn ->
          assert_raise Mix.Error, ~r/specs.check failed with 1 missing @spec declaration/, fn ->
            Check.run(["--paths", "src"])
          end
        end)

      assert error_output =~ "src/sample.ex:2 missing @spec for Sample.missing/1"
    end)
  end

  test "loads exemptions from a file and ignores comments and blank lines" do
    in_temp_project(fn ->
      write_module!("lib/sample.ex", """
      defmodule Sample do
        def skipped_sample(arg), do: arg
      end
      """)

      File.mkdir_p!("config")

      File.write!("config/specs_exemptions.txt", """
      # existing exemptions

      Sample.skipped_sample/1
      """)

      output =
        capture_io(fn ->
          assert :ok = Check.run(["--paths", "lib", "--exemptions-file", "config/specs_exemptions.txt"])
        end)

      assert output =~ "specs.check: all public functions have @spec or exemption"
    end)
  end

  test "treats a missing exemptions file as empty" do
    in_temp_project(fn ->
      write_module!("lib/sample.ex", """
      defmodule Sample do
        @spec ok(term()) :: term()
        def ok(arg), do: arg
      end
      """)

      output =
        capture_io(fn ->
          assert :ok = Check.run(["--exemptions-file", "config/missing.txt"])
        end)

      assert output =~ "specs.check: all public functions have @spec or exemption"
    end)
  end

  test "raises when repository docs link to the private spec corpus" do
    in_temp_project(fn ->
      spec_doc = spec_doc_path()
      target = "../" <> spec_doc

      write_module!(spec_doc, "# Core Spec\n")
      write_module!(Path.join("docs", "architecture.md"), "[Core spec](#{target})\n")

      error_output =
        capture_io(:stderr, fn ->
          assert_raise Mix.Error, ~r/0 missing @spec declaration\(s\) and 1 spec corpus boundary violation/, fn ->
            Check.run([])
          end
        end)

      assert error_output =~ "docs/architecture.md:1 files outside specs/ must not link to private spec corpus files"
    end)
  end

  defp in_temp_project(fun) do
    root = Path.join(System.tmp_dir!(), "specs-check-task-test-#{System.unique_integer([:positive, :monotonic])}")
    original_cwd = File.cwd!()

    File.rm_rf!(root)
    File.mkdir_p!(root)

    try do
      File.cd!(root, fun)
    after
      File.cd!(original_cwd)
      File.rm_rf!(root)
    end
  end

  defp write_module!(path, source) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, source)
  end

  defp spec_doc_path do
    Path.join("spec" <> "s", "SPEC.md")
  end
end
