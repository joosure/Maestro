defmodule SymphonyElixir.WorkspaceAutomationTest do
  use ExUnit.Case, async: true

  @automation_root Path.expand("priv/workspace_automation", File.cwd!())

  @forbidden_runtime_references [
    {Regex.compile!("(^|[^[:alnum:]_])(?:\\.\\./)?" <> ("spe" <> "cs") <> "/"), "repository-local private asset path"},
    {~r/\b[A-Za-z0-9_]+_spec\.md\b/, "spec markdown file"},
    {Regex.compile!("\\b" <> ("SP" <> "EC.md") <> "\\b"), "top-level private asset entrypoint"},
    {~r/\bAGENTS\.md\b/, "repository-local AGENTS.md"},
    {~r/\bsource repository\b/i, "source repository documentation"},
    {Regex.compile!("\\bintegration " <> "specification\\b", "i"), "private integration documentation"},
    {Regex.compile!("\\brepository TAPD " <> "integration\\b", "i"), "repo-local TAPD integration marker"},
    {~r/\bSymphony's own repo\b/i, "Symphony repository-specific policy"},
    {~r/\bSymphonyElixir\b/, "internal Elixir module reference"},
    {~r/\bshared Symphony logging conventions\b/i, "internal logging convention reference"},
    {~r/\bfollow-up\|symphony\b/i, "Symphony-specific example label"},
    {~r/\bcd elixir\b/, "Symphony checkout-specific elixir directory"},
    {~r/\bmake e2e-[A-Za-z0-9_-]+\b/, "Symphony checkout-specific e2e harness"},
    {~r/\belixir && mix\b/, "Symphony checkout-specific mix command"}
  ]

  test "bundled workspace automation is self-contained runtime guidance" do
    violations =
      @automation_root
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.flat_map(&runtime_reference_violations/1)

    assert violations == []
  end

  defp runtime_reference_violations(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      @forbidden_runtime_references
      |> Enum.filter(fn {pattern, _label} -> Regex.match?(pattern, line) end)
      |> Enum.map(fn {_pattern, label} ->
        "#{Path.relative_to_cwd(path)}:#{line_number} references #{label}: #{String.trim(line)}"
      end)
    end)
  end
end
