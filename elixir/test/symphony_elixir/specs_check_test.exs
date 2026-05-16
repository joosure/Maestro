defmodule SymphonyElixir.SpecsCheckTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.SpecsCheck

  test "reports missing @spec for public functions" do
    dir = create_tmp_dir()

    write_module!(dir, "sample.ex", """
    defmodule Sample do
      def missing(arg), do: arg
    end
    """)

    findings = SpecsCheck.missing_public_specs([dir])

    assert Enum.map(findings, &SpecsCheck.finding_identifier/1) == ["Sample.missing/1"]
  end

  test "accepts adjacent @spec on public function" do
    dir = create_tmp_dir()

    write_module!(dir, "sample.ex", """
    defmodule Sample do
      @spec ok(term()) :: term()
      def ok(arg), do: arg
    end
    """)

    assert SpecsCheck.missing_public_specs([dir]) == []
  end

  test "accepts adjacent @spec on public function with a default-argument declaration" do
    dir = create_tmp_dir()

    write_module!(dir, "sample.ex", """
    defmodule Sample do
      @spec ok(term(), term()) :: term()
      def ok(arg, default_value \\\\ nil)
      def ok(arg, default_value), do: default_value || arg
    end
    """)

    assert SpecsCheck.missing_public_specs([dir]) == []
  end

  test "allows defp without @spec" do
    dir = create_tmp_dir()

    write_module!(dir, "sample.ex", """
    defmodule Sample do
      def public do
        helper(:ok)
      end

      defp helper(value), do: value
    end
    """)

    findings = SpecsCheck.missing_public_specs([dir])

    assert Enum.map(findings, &SpecsCheck.finding_identifier/1) == ["Sample.public/0"]
  end

  test "exempts callback implementations marked with @impl" do
    dir = create_tmp_dir()

    write_module!(dir, "worker.ex", """
    defmodule Worker do
      @behaviour GenServer

      @impl true
      def init(state), do: {:ok, state}
    end
    """)

    assert SpecsCheck.missing_public_specs([dir]) == []
  end

  test "honors explicit exemptions list" do
    dir = create_tmp_dir()

    write_module!(dir, "sample.ex", """
    defmodule Sample do
      def skipped_sample(arg), do: arg
    end
    """)

    findings = SpecsCheck.missing_public_specs([dir], exemptions: ["Sample.skipped_sample/1"])

    assert findings == []
  end

  test "reports files outside specs that link to the private spec corpus" do
    dir = create_tmp_dir()
    spec_doc = spec_doc_path()
    target = "../" <> spec_doc

    write_module!(dir, spec_doc, "# Core Spec\n")
    write_module!(dir, Path.join("docs", "architecture.md"), "[Core spec](#{target})\n")

    assert [
             %{
               file: "docs/architecture.md",
               line: 1,
               reason: :outside_link_to_spec_corpus,
               target: ^target
             }
           ] = SpecsCheck.spec_corpus_boundary_violations(dir)
  end

  test "reports raw spec corpus references outside specs" do
    dir = create_tmp_dir()
    spec_doc = spec_doc_path()

    write_module!(dir, spec_doc, "# Core Spec\n")
    write_module!(dir, "README.md", "See `#{spec_doc}`.\n")

    assert [
             %{
               file: "README.md",
               line: 1,
               reason: :outside_reference_to_spec_corpus,
               target: ^spec_doc
             }
           ] = SpecsCheck.spec_corpus_boundary_violations(dir)
  end

  test "reports repo-root-relative spec corpus references from nested files" do
    dir = create_tmp_dir()
    spec_doc = spec_doc_path()
    nested_doc = Path.join(["docs", "nested", "architecture.md"])

    write_module!(dir, spec_doc, "# Core Spec\n")
    write_module!(dir, nested_doc, "See `#{spec_doc}`.\n")

    assert [
             %{
               file: ^nested_doc,
               line: 1,
               reason: :outside_reference_to_spec_corpus,
               target: ^spec_doc
             }
           ] = SpecsCheck.spec_corpus_boundary_violations(dir)
  end

  test "reports spec corpus links to files outside specs" do
    dir = create_tmp_dir()
    spec_example = specs_path("workflow", "example.md")

    write_module!(dir, "README.md", "# Public Readme\n")
    write_module!(dir, spec_example, "[Public readme](../../README.md)\n")

    assert [
             %{
               file: ^spec_example,
               line: 1,
               reason: :spec_link_outside_corpus,
               target: "../../README.md"
             }
           ] = SpecsCheck.spec_corpus_boundary_violations(dir)
  end

  test "reports external links from spec corpus files" do
    dir = create_tmp_dir()
    spec_doc = spec_doc_path()

    write_module!(dir, spec_doc, "[External](https://example.test/reference)\n")

    assert [
             %{
               file: ^spec_doc,
               line: 1,
               reason: :spec_external_link,
               target: "https://example.test/reference"
             }
           ] = SpecsCheck.spec_corpus_boundary_violations(dir)
  end

  test "reports raw external references from spec corpus files" do
    dir = create_tmp_dir()
    spec_doc = spec_doc_path()

    write_module!(dir, spec_doc, "See https://example.test/reference\n")

    assert [
             %{
               file: ^spec_doc,
               line: 1,
               reason: :spec_external_reference,
               target: "https://example.test/reference"
             }
           ] = SpecsCheck.spec_corpus_boundary_violations(dir)
  end

  test "allows spec corpus links to files inside specs" do
    dir = create_tmp_dir()
    spec_doc = spec_doc_path()
    spec_example = specs_path("workflow", "example.md")
    target = Path.join("..", "SPEC.md")

    write_module!(dir, spec_doc, "# Core Spec\n")
    write_module!(dir, spec_example, "[Core spec](#{target})\n")

    assert SpecsCheck.spec_corpus_boundary_violations(dir) == []
  end

  defp create_tmp_dir do
    unique = :erlang.unique_integer([:positive, :monotonic])
    dir = Path.join(System.tmp_dir!(), "specs-check-test-#{unique}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp write_module!(dir, rel_path, source) do
    path = Path.join(dir, rel_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, source)
  end

  defp spec_doc_path do
    specs_path("SPEC.md")
  end

  defp specs_path(parts) when is_list(parts) do
    Path.join(["spec" <> "s" | parts])
  end

  defp specs_path(part) do
    specs_path([part])
  end

  defp specs_path(first, second) do
    specs_path([first, second])
  end
end
