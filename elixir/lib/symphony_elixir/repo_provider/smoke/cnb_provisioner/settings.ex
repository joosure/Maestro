defmodule SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.Settings do
  @moduledoc false

  @default_web_base_url "https://cnb.cool"
  @branch_prefix "repo-provider-smoke/cnb-pipeline"
  @poll_interval_ms 5_000
  @timeout_ms 120_000
  @commit_message "repo-provider smoke: auto-provision temporary .cnb.yml"
  @git_user_name "Symphony Smoke"
  @git_user_email "repo-provider-smoke@example.invalid"
  @pipeline """
  $:
    push:
      - name: repo-provider-probe-push
        stages:
          - name: probe
            image: alpine:3.20
            script: |
              echo "repo-provider probe push"
              echo "branch=$CNB_BRANCH"
    pull_request:
      - name: repo-provider-probe-pr
        stages:
          - name: probe
            image: alpine:3.20
            script: |
              echo "repo-provider probe pull_request"
              echo "branch=$CNB_BRANCH"
              echo "pull_request=$CNB_PULL_REQUEST"
              echo "pr_branch=$CNB_PULL_REQUEST_BRANCH"
  """

  @spec default_web_base_url() :: String.t()
  def default_web_base_url, do: @default_web_base_url

  @spec branch_prefix() :: String.t()
  def branch_prefix, do: @branch_prefix

  @spec poll_interval_ms() :: pos_integer()
  def poll_interval_ms, do: @poll_interval_ms

  @spec timeout_ms() :: pos_integer()
  def timeout_ms, do: @timeout_ms

  @spec commit_message() :: String.t()
  def commit_message, do: @commit_message

  @spec git_user_name() :: String.t()
  def git_user_name, do: @git_user_name

  @spec git_user_email() :: String.t()
  def git_user_email, do: @git_user_email

  @spec pipeline() :: String.t()
  def pipeline, do: @pipeline
end
