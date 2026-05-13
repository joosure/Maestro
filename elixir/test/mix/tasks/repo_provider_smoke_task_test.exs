defmodule Mix.Tasks.RepoProvider.SmokeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.RepoProvider.Smoke, as: RepoProviderSmokeTask

  setup do
    Mix.Task.reenable("repo_provider.smoke")
    :ok
  end

  test "prints help" do
    output = capture_io(fn -> RepoProviderSmokeTask.run(["--help"]) end)
    assert output =~ "mix repo_provider.smoke"
    assert output =~ "--pr <number>"
    assert output =~ "--auto-provision-cnb-pipeline"
  end

  test "runs GitHub smoke probes and prints JSON output" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-smoke-task-#{unique}")
    bin_dir = Path.join(root, "bin")
    gh_path = Path.join(bin_dir, "gh")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)

      write_executable!(
        gh_path,
        """
        #!/bin/sh
        if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
          printf 'Logged in to github.com as smoke-user\\n'
          exit 0
        fi
        if [ "$1" = "pr" ] && [ "$2" = "view" ] && [ "$3" = "42" ]; then
          printf '{"url":"https://github.com/acme/widgets/pull/42","state":"OPEN","title":"Repo provider refactor","body":"Implements Elixir backend","headRefName":"feature/backend","headRefOid":"abc123","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN"}\\n'
          exit 0
        fi
        if [ "$1" = "api" ] && [ "$2" = "repos/acme/widgets/pulls/42/reviews" ]; then
          printf '[{"id":9,"body":"looks good","submitted_at":"2026-04-23T00:05:00Z","state":"approved","user":{"login":"reviewer","type":"User"}}]\\n'
          exit 0
        fi
        if [ "$1" = "pr" ] && [ "$2" = "checks" ] && [ "$3" = "42" ]; then
          printf '[{"bucket":"pass","completedAt":"2026-04-23T00:21:00Z","description":"green","link":"https://ci.example.test/runs/1","name":"ci","startedAt":"2026-04-23T00:20:00Z","state":"SUCCESS"}]\\n'
          exit 0
        fi
        printf 'unexpected gh invocation: %s\\n' "$*" >&2
        exit 99
        """
      )

      output =
        with_env(
          %{
            "PATH" => Enum.join([bin_dir, System.get_env("PATH") || ""], ":"),
            "SYMPHONY_REPO_PROVIDER_KIND" => "github"
          },
          fn ->
            capture_io(fn ->
              RepoProviderSmokeTask.run(["--provider", "github", "--repo", "acme/widgets", "--pr", "42", "--json"])
            end)
          end
        )

      payload = Jason.decode!(output)

      assert payload["ok"] == true
      assert payload["provider_kind"] == "github"
      assert payload["repo_provider_runtime"] == "symphony"
      assert payload["repository"] == "acme/widgets"
      assert payload["smoke_mode"] == "read_only"
      assert payload["probe_count"] == 5
      assert payload["passed_count"] == 5

      assert Enum.map(payload["probes"], & &1["id"]) == [
               "current-kind",
               "auth-status",
               "pr-view",
               "pr-reviews",
               "pr-checks"
             ]

      assert Enum.find(payload["probes"], &(&1["id"] == "pr-view"))["summary"] ==
               "https://github.com/acme/widgets/pull/42"

      assert Enum.find(payload["probes"], &(&1["id"] == "pr-reviews"))["summary"] ==
               "APPROVED"

      assert Enum.find(payload["probes"], &(&1["id"] == "pr-checks"))["summary"] ==
               "ci: completed/success (green)"
    after
      File.rm_rf!(root)
    end
  end

  defp write_executable!(path, contents) do
    File.write!(path, contents)
    File.chmod!(path, 0o755)
  end

  defp with_env(overrides, fun) do
    keys = Map.keys(overrides)
    previous = Map.new(keys, fn key -> {key, System.get_env(key)} end)

    try do
      Enum.each(overrides, fn {key, value} -> System.put_env(key, value) end)
      fun.()
    after
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end
end
