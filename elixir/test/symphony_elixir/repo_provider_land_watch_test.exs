defmodule SymphonyElixir.RepoProviderLandWatchTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.CLI.RepoProvider, as: RepoProviderCLI
  alias SymphonyElixir.RepoProvider.Invocation
  alias SymphonyElixir.RepoProvider.LandWatch
  alias SymphonyElixir.RepoProvider.LandWatch.{Checks, Reviews}

  setup do
    keys = [
      :memory_repo_provider_pr,
      :memory_repo_provider_issue_comments,
      :memory_repo_provider_review_comments,
      :memory_repo_provider_reviews,
      :memory_repo_provider_checks
    ]

    on_exit(fn ->
      Enum.each(keys, &Application.delete_env(:symphony_elixir, &1))
    end)

    :ok
  end

  test "parses pr-land-watch options" do
    assert {:ok,
            %Invocation{
              command: :pr_land_watch,
              number: "42",
              poll_ms: 500,
              checks_appear_timeout_ms: 2_000
            }} =
             Invocation.parse([
               "pr-land-watch",
               "42",
               "--poll-ms",
               "500",
               "--checks-appear-timeout-ms",
               "2000"
             ])
  end

  test "dedupes check runs by latest timestamp before summarizing" do
    assert %{pending?: false, failed?: false, failures: []} =
             Checks.summarize([
               %{
                 "name" => "ci",
                 "status" => "completed",
                 "conclusion" => "failure",
                 "completed_at" => "2026-04-23T00:00:00Z"
               },
               %{
                 "name" => "ci",
                 "status" => "completed",
                 "conclusion" => "success",
                 "completed_at" => "2026-04-23T00:05:00Z"
               }
             ])
  end

  test "review evaluator blocks unresolved human feedback" do
    settings = Reviews.settings_from_env(%{})

    assert {:blocked, 2, message} =
             Reviews.evaluate(
               [
                 %{
                   "id" => 1,
                   "body" => "please fix",
                   "created_at" => "2026-04-23T00:00:00Z",
                   "user" => %{"login" => "reviewer", "type" => "User"}
                 }
               ],
               [],
               [],
               settings
             )

    assert IO.iodata_to_binary(message) =~ "Review comments detected"
  end

  test "land watcher exits successfully when checks pass and reviews are clear" do
    configure_memory_pr()

    Application.put_env(:symphony_elixir, :memory_repo_provider_checks, [
      %{"name" => "ci", "status" => "completed", "conclusion" => "success"}
    ])

    assert {:ok, output, 0} =
             LandWatch.watch(memory_repo(), env: %{}, sleep_fn: fn _ms -> :ok end)

    assert output =~ "Waiting for review feedback"
    assert output =~ "Checks passed"
  end

  test "land watcher times out when checks never appear" do
    configure_memory_pr()
    Application.put_env(:symphony_elixir, :memory_repo_provider_checks, [])

    assert {:ok, output, 3} =
             LandWatch.watch(memory_repo(),
               env: %{},
               poll_ms: 1,
               checks_appear_timeout_ms: 1,
               sleep_fn: fn _ms -> :ok end
             )

    assert output =~ "No checks detected"
  end

  test "repo-provider CLI exposes pr-land-watch through command dispatch" do
    configure_memory_pr()

    Application.put_env(:symphony_elixir, :memory_repo_provider_checks, [
      %{"name" => "ci", "status" => "completed", "conclusion" => "success"}
    ])

    assert {output, "", 0} =
             RepoProviderCLI.evaluate(["pr-land-watch"], cli_deps(%{"SYMPHONY_REPO_PROVIDER_KIND" => "memory"}))

    assert output =~ "Checks passed"
  end

  defp configure_memory_pr do
    Application.put_env(:symphony_elixir, :memory_repo_provider_pr, %{
      "number" => 35,
      "url" => "https://example.test/pr/35",
      "headRefOid" => "abc123",
      "mergeable" => "MERGEABLE",
      "mergeStateStatus" => "CLEAN"
    })

    Application.put_env(:symphony_elixir, :memory_repo_provider_issue_comments, [])
    Application.put_env(:symphony_elixir, :memory_repo_provider_review_comments, [])
    Application.put_env(:symphony_elixir, :memory_repo_provider_reviews, [])
  end

  defp memory_repo, do: %{provider: %{kind: "memory"}}

  defp cli_deps(env) do
    %{
      env: fn -> env end,
      command_opts: fn -> [env: env, sleep_fn: fn _ms -> :ok end] end,
      stdout: fn _output -> :ok end,
      stderr: fn _output -> :ok end,
      halt: fn _status -> raise "halt should not be called from evaluate/2" end
    }
  end
end
