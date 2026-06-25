defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ChangeProposalReconcileTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ChangeProposalReconcile

  test "runs one-shot command through validated deps" do
    parent = self()
    report = fake_report("issue-123", shadow?: false)

    deps = %{
      one_shot_run: fn opts ->
        send(parent, {:one_shot_opts, opts})
        report
      end
    }

    assert {stdout, "", 0} =
             ChangeProposalReconcile.evaluate(["--issue", "issue-123"], deps: deps)

    assert stdout =~ "change proposal one-shot"
    assert stdout =~ "issue=issue-123"

    assert_receive {:one_shot_opts,
                    [
                      issue_id: "issue-123",
                      confirm_state_write: false
                    ]}
  end

  test "dry-run text output is marked as shadow no-write diagnostic evidence" do
    report = fake_report("issue-shadow", shadow?: true)

    assert {stdout, "", 0} =
             ChangeProposalReconcile.evaluate(["--issue", "issue-shadow"], deps: %{one_shot_run: fn _opts -> report end})

    for line <- String.split(String.trim(stdout), "\n") do
      assert String.starts_with?(line, "[SHADOW_MODE_ONLY - NO PRODUCTION WRITE]")
      assert line =~ "shadow_run_id=shadow-test-run"
      assert line =~ "shadow_authority=diagnostic_only"
    end
  end

  test "dry-run text output preserves Linear + CNB shadow provider identity" do
    report = fake_report("issue-linear-cnb-shadow", shadow?: true, tracker_kind: "linear", repo_provider_kind: "cnb")

    assert {stdout, "", 0} =
             ChangeProposalReconcile.evaluate(["--issue", "issue-linear-cnb-shadow"],
               deps: %{one_shot_run: fn _opts -> report end}
             )

    for line <- String.split(String.trim(stdout), "\n") do
      assert String.starts_with?(line, "[SHADOW_MODE_ONLY - NO PRODUCTION WRITE]")
      assert line =~ "shadow_run_id=shadow-test-run"
      assert line =~ "shadow_authority=diagnostic_only"
    end

    assert stdout =~ "issue=issue-linear-cnb-shadow"
    assert stdout =~ "tracker=linear repo_provider=cnb"
    refute stdout =~ "state_write"
  end

  test "dry-run json output carries shadow no-write isolation metadata" do
    report = fake_report("issue-shadow-json", shadow?: true)

    assert {stdout, "", 0} =
             ChangeProposalReconcile.evaluate(["--issue", "issue-shadow-json", "--json"],
               deps: %{one_shot_run: fn _opts -> report end}
             )

    decoded = Jason.decode!(stdout)

    assert decoded["shadow"]["prefix"] == "[SHADOW_MODE_ONLY - NO PRODUCTION WRITE]"
    assert decoded["shadow"]["run_id"] == "shadow-test-run"
    assert decoded["shadow"]["authority"] == "diagnostic_only"
    assert decoded["shadow"]["canonical_authority"] == false

    assert decoded["shadow"]["allowed_destinations"] == [
             "diagnostic_logs",
             "review_packets",
             "non_authoritative_evidence"
           ]
  end

  test "dry-run json output preserves Linear + CNB shadow provider identity" do
    report = fake_report("issue-linear-cnb-shadow-json", shadow?: true, tracker_kind: "linear", repo_provider_kind: "cnb")

    assert {stdout, "", 0} =
             ChangeProposalReconcile.evaluate(["--issue", "issue-linear-cnb-shadow-json", "--json"],
               deps: %{one_shot_run: fn _opts -> report end}
             )

    decoded = Jason.decode!(stdout)

    assert decoded["issue_id"] == "issue-linear-cnb-shadow-json"
    assert decoded["mode"] == "dry_run"
    assert decoded["tracker_kind"] == "linear"
    assert decoded["repo_provider_kind"] == "cnb"
    assert decoded["shadow"]["prefix"] == "[SHADOW_MODE_ONLY - NO PRODUCTION WRITE]"
    assert decoded["shadow"]["run_id"] == "shadow-test-run"
    assert decoded["shadow"]["authority"] == "diagnostic_only"
    assert decoded["shadow"]["canonical_authority"] == false
    refute stdout =~ "state_write"
  end

  test "rejects non-keyword command opts without leaking raw opts" do
    assert {"", stderr, 70} = ChangeProposalReconcile.evaluate(["--issue", "issue-123"], [:secret_opts])

    assert stderr =~ "reason=command_opts_not_keyword"
    assert stderr =~ "value_type=list"
    refute stderr =~ "secret_opts"
  end

  test "rejects missing deps without leaking raw deps" do
    assert {"", stderr, 70} = ChangeProposalReconcile.evaluate(["--issue", "issue-123"], deps: %{secret: true})

    assert stderr =~ "reason=deps_invalid"
    assert stderr =~ "value_type=map"
    refute stderr =~ "secret"
  end

  test "rejects invalid one-shot dependency without leaking raw value" do
    assert {"", stderr, 70} =
             ChangeProposalReconcile.evaluate(["--issue", "issue-123"], deps: %{one_shot_run: :secret_runner})

    assert stderr =~ "reason=one_shot_run_not_function"
    assert stderr =~ "value_type=atom"
    refute stderr =~ "secret_runner"
  end

  test "does not echo unexpected command arguments" do
    assert {"", stderr, 64} =
             ChangeProposalReconcile.evaluate(["--issue", "issue-123", "secret-extra"], deps: valid_deps())

    assert stderr =~ "Unexpected argument count: 1"
    refute stderr =~ "secret-extra"
  end

  test "does not echo invalid command options" do
    assert {"", stderr, 64} =
             ChangeProposalReconcile.evaluate(["--secret-option", "secret-value", "--issue", "issue-123"], deps: valid_deps())

    assert stderr =~ "Invalid option count:"
    refute stderr =~ "--secret-option"
    refute stderr =~ "secret-value"
  end

  test "rejects argv lists containing non-strings" do
    assert {"", stderr, 64} = ChangeProposalReconcile.evaluate(["--issue", :secret_issue], deps: valid_deps())

    assert stderr =~ "Command argv must contain only strings"
    assert stderr =~ "value_type=atom"
    refute stderr =~ "secret_issue"
  end

  defp valid_deps do
    %{one_shot_run: fn _opts -> fake_report("issue-123", shadow?: false) end}
  end

  defp fake_report(issue_id, opts) do
    %{
      ok: true,
      issue_id: issue_id,
      mode: "dry_run",
      shadow: shadow(opts),
      tracker_kind: Keyword.get(opts, :tracker_kind, "memory"),
      repo_provider_kind: Keyword.get(opts, :repo_provider_kind, "memory"),
      before_state: "In Review",
      after_state: "In Review",
      decision: nil,
      transition: nil,
      probes: []
    }
  end

  defp shadow(opts) do
    if Keyword.fetch!(opts, :shadow?) do
      %{
        "prefix" => "[SHADOW_MODE_ONLY - NO PRODUCTION WRITE]",
        "run_id" => "shadow-test-run",
        "mode" => "shadow_no_write",
        "authority" => "diagnostic_only",
        "canonical_authority" => false,
        "allowed_destinations" => ["diagnostic_logs", "review_packets", "non_authoritative_evidence"]
      }
    end
  end
end
