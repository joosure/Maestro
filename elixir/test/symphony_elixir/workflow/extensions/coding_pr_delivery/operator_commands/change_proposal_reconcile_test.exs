defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ChangeProposalReconcileTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ChangeProposalReconcile

  test "runs one-shot command through validated deps" do
    parent = self()
    report = fake_report("issue-123")

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
    %{one_shot_run: fn _opts -> fake_report("issue-123") end}
  end

  defp fake_report(issue_id) do
    %{
      ok: true,
      issue_id: issue_id,
      mode: "dry_run",
      tracker_kind: "memory",
      repo_provider_kind: "memory",
      before_state: "In Review",
      after_state: "In Review",
      decision: nil,
      transition: nil,
      probes: []
    }
  end
end
