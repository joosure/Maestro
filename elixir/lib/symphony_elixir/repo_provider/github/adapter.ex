defmodule SymphonyElixir.RepoProvider.GitHub.Adapter do
  @moduledoc """
  GitHub-backed repo-provider adapter.

  Implements `SymphonyElixir.RepoProvider.Adapter` for GitHub.
  This module acts as a thin orchestrator that delegates to
  responsibility-specific handler modules:

    * `GitHub.PullRequestHandler` — PR lifecycle (view, create, edit, close, merge, checks)
    * `GitHub.RunHandler` — CI run introspection (list, view, logs)
    * `GitHub.ApiHandler` — generic API proxying and endpoint template expansion

  CLI infrastructure is encapsulated in `GitHub.CLI` and data
  normalization in `GitHub.Normalizer`.
  """

  @behaviour SymphonyElixir.RepoProvider.Adapter

  alias SymphonyElixir.RepoProvider.ConfigValidator
  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.GitHub.ApiHandler
  alias SymphonyElixir.RepoProvider.GitHub.CLI
  alias SymphonyElixir.RepoProvider.GitHub.PullRequestHandler
  alias SymphonyElixir.RepoProvider.GitHub.RunHandler
  alias SymphonyElixir.RepoProvider.Kinds

  @type repo_config :: map()
  @capabilities SymphonyElixir.RepoProvider.Adapter.all_capabilities()
  @provider_kind Kinds.github()

  # ── Required ─────────────────────────────────────────────────────

  @impl true
  def kind, do: @provider_kind

  @impl true
  def defaults, do: %{}

  @impl true
  def validate_config(repo), do: ConfigValidator.validate(repo, __MODULE__)

  @impl true
  def capabilities, do: @capabilities

  @impl true
  def supported_config_options, do: [:required_pr_label, :change_proposal_body_generator]

  # ── Auth & Health ────────────────────────────────────────────────

  @impl true
  def healthcheck(_repo, opts \\ []) do
    case CLI.run_command("gh", ["auth", "status"], opts) do
      {:ok, _output} ->
        :ok

      {:error, {:enoent, _output}} ->
        {:error, CLI.enoent_error()}

      {:error, {_status, output}} ->
        {:error, Error.runtime_failure(:github_auth_failed, String.trim(output))}
    end
  end

  @impl true
  def auth_status(_repo, opts \\ []) do
    case CLI.run_command("gh", ["auth", "status"], opts) do
      {:ok, output} ->
        {:ok, String.trim_trailing(output, "\n")}

      {:error, {:enoent, _output}} ->
        {:error, CLI.enoent_error()}

      {:error, {_status, output}} ->
        {:error, Error.runtime_failure(:github_auth_status_failed, String.trim(output))}
    end
  end

  # ── PR Operations (delegated to PullRequestHandler) ──────────────

  @impl true
  def pr_view(repo, opts \\ []) when is_map(repo),
    do: PullRequestHandler.pr_view(repo, opts)

  @impl true
  def pr_create(repo, opts \\ []) when is_map(repo),
    do: PullRequestHandler.pr_create(repo, opts)

  @impl true
  def pr_edit(repo, opts \\ []) when is_map(repo),
    do: PullRequestHandler.pr_edit(repo, opts)

  @impl true
  def pr_add_label(repo, opts \\ []) when is_map(repo),
    do: PullRequestHandler.pr_add_label(repo, opts)

  @impl true
  def pr_issue_comments(repo, opts \\ []) when is_map(repo),
    do: ApiHandler.pr_issue_comments(repo, opts)

  @impl true
  def pr_add_issue_comment(repo, opts \\ []) when is_map(repo),
    do: ApiHandler.pr_add_issue_comment(repo, opts)

  @impl true
  def pr_reviews(repo, opts \\ []) when is_map(repo),
    do: ApiHandler.pr_reviews(repo, opts)

  @impl true
  def pr_submit_review(repo, opts \\ []) when is_map(repo),
    do: ApiHandler.pr_submit_review(repo, opts)

  @impl true
  def pr_review_comments(repo, opts \\ []) when is_map(repo),
    do: ApiHandler.pr_review_comments(repo, opts)

  @impl true
  def pr_reply_review_comment(repo, opts \\ []) when is_map(repo),
    do: ApiHandler.pr_reply_review_comment(repo, opts)

  @impl true
  def pr_close(repo, opts \\ []) when is_map(repo),
    do: PullRequestHandler.pr_close(repo, opts)

  @impl true
  def pr_merge(repo, opts \\ []) when is_map(repo),
    do: PullRequestHandler.pr_merge(repo, opts)

  @impl true
  def pr_checks(repo, opts \\ []) when is_map(repo),
    do: PullRequestHandler.pr_checks(repo, opts)

  # ── API Operations (delegated to ApiHandler) ─────────────────────

  @impl true
  def api(repo, opts \\ []) when is_map(repo),
    do: ApiHandler.api(repo, opts)

  # ── Run Operations (delegated to RunHandler) ─────────────────────

  @impl true
  def run_list(repo, opts \\ []) when is_map(repo),
    do: RunHandler.run_list(repo, opts)

  @impl true
  def run_view(repo, opts \\ []) when is_map(repo),
    do: RunHandler.run_view(repo, opts)

  # ── Lifecycle ────────────────────────────────────────────────────

  @impl true
  def close_open_pull_requests_for_branch(repo, branch, opts \\ [])
      when is_map(repo) and is_binary(branch),
      do: PullRequestHandler.close_open_pull_requests_for_branch(repo, branch, opts)

  # ── Public: Repository Resolution ────────────────────────────────

  @spec resolve_repository(repo_config(), keyword()) :: String.t() | nil
  defdelegate resolve_repository(repo, opts \\ []), to: CLI

  @spec configured_repository(repo_config()) :: String.t() | nil
  defdelegate configured_repository(repo), to: CLI

  @spec parse_repository_slug(String.t()) :: String.t() | nil
  defdelegate parse_repository_slug(remote_url), to: CLI
end
