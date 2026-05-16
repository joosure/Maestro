defmodule Mix.Tasks.Specs.Check do
  use Mix.Task

  alias SymphonyElixir.SpecsCheck

  @moduledoc """
  Enforces adjacent `@spec` declarations for public APIs in `lib/` and
  validates private spec-corpus link boundaries when a repository-level
  `specs/` directory is present.
  """
  @shortdoc "Fails on missing @specs or spec-corpus boundary violations"

  @switches [paths: :keep, exemptions_file: :string]
  @default_paths ["lib"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} = OptionParser.parse(args, strict: @switches)

    paths = Keyword.get_values(opts, :paths)
    scanned_paths = if paths == [], do: @default_paths, else: paths

    exemptions =
      case Keyword.get(opts, :exemptions_file) do
        nil -> MapSet.new()
        path -> load_exemptions(path)
      end

    findings = SpecsCheck.missing_public_specs(scanned_paths, exemptions: exemptions)
    boundary_violations = SpecsCheck.spec_corpus_boundary_violations(File.cwd!())

    if findings == [] and boundary_violations == [] do
      Mix.shell().info("specs.check: all public functions have @spec or exemption and spec corpus boundaries are valid")
      :ok
    else
      Enum.each(findings, fn finding ->
        Mix.shell().error("#{finding.file}:#{finding.line} missing @spec for #{SpecsCheck.finding_identifier(finding)}")
      end)

      Enum.each(boundary_violations, fn violation ->
        Mix.shell().error(SpecsCheck.boundary_violation_message(violation))
      end)

      Mix.raise("specs.check failed with #{length(findings)} missing @spec declaration(s) and #{length(boundary_violations)} spec corpus boundary violation(s)")
    end
  end

  defp load_exemptions(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> MapSet.new()
    else
      MapSet.new()
    end
  end
end
