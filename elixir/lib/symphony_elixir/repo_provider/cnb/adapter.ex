defmodule SymphonyElixir.RepoProvider.CNB.Adapter do
  @moduledoc """
  CNB (Cloud Native Build) repo-provider adapter.

  Implements `SymphonyElixir.RepoProvider.Adapter` for the CNB code-hosting
  platform. This module acts as a thin orchestrator that delegates to
  responsibility-specific handler modules:

    * `CNB.PullRequestHandler` — PR lifecycle (view, create, edit, close, merge, checks)
    * `CNB.RunHandler` — CI run introspection (list, view, logs)
    * `CNB.ApiHandler` — generic API proxying and GitHub-style endpoint translation

  HTTP infrastructure is encapsulated in `CNB.HttpClient` and data
  normalization in `CNB.Normalizer`.
  """

  @behaviour SymphonyElixir.RepoProvider.Adapter

  alias SymphonyElixir.Repo, as: TargetRepo
  alias SymphonyElixir.Repo.Context, as: RepoContext
  alias SymphonyElixir.RepoProvider.CNB.ApiHandler
  alias SymphonyElixir.RepoProvider.CNB.HttpClient
  alias SymphonyElixir.RepoProvider.CNB.Normalizer
  alias SymphonyElixir.RepoProvider.CNB.PullRequestHandler
  alias SymphonyElixir.RepoProvider.CNB.RunHandler
  alias SymphonyElixir.RepoProvider.Config, as: RepoConfig
  alias SymphonyElixir.RepoProvider.ConfigValidator
  alias SymphonyElixir.RepoProvider.Error

  @type repo_config :: map()
  @capabilities SymphonyElixir.RepoProvider.Adapter.all_capabilities() --
                  [:pr_add_label, :pr_submit_review]

  @impl true
  def kind, do: "cnb"

  @impl true
  def defaults, do: %{}

  @impl true
  def validate_config(repo), do: ConfigValidator.validate(repo, __MODULE__)

  @impl true
  def capabilities, do: @capabilities

  @impl true
  def supported_config_options, do: [:change_proposal_body_generator]

  @impl true
  def healthcheck(repo, opts \\ []) do
    with_token(opts, fn token ->
      with {:ok, _payload} <- HttpClient.get_json(repo, "/user", token, opts) do
        :ok
      end
    end)
  end

  @impl true
  def auth_status(repo, opts \\ []) do
    with_token(opts, fn token ->
      with {:ok, payload} <- HttpClient.get_json(repo, "/user", token, opts) do
        username = payload["username"] || get_in(payload, ["data", "username"]) || "unknown"
        {:ok, "CNB auth ok as #{username}"}
      end
    end)
  end

  # ── PR Operations (delegated to PullRequestHandler) ──────────────

  @impl true
  def pr_view(repo, opts \\ []) when is_map(repo) do
    with_repo_context(repo, opts, fn repository, token ->
      PullRequestHandler.pr_view(repo, repository, token, opts)
    end)
  end

  @impl true
  def pr_create(repo, opts \\ []) when is_map(repo) do
    with_repo_context(repo, opts, fn repository, token ->
      PullRequestHandler.pr_create(repo, repository, token, opts)
    end)
  end

  @impl true
  def pr_edit(repo, opts \\ []) when is_map(repo) do
    with_repo_context(repo, opts, fn repository, token ->
      PullRequestHandler.pr_edit(repo, repository, token, opts)
    end)
  end

  @impl true
  def pr_close(repo, opts \\ []) when is_map(repo) do
    with_repo_context(repo, opts, fn repository, token ->
      PullRequestHandler.pr_close(repo, repository, token, opts)
    end)
  end

  @impl true
  def pr_merge(repo, opts \\ []) when is_map(repo) do
    with_repo_context(repo, opts, fn repository, token ->
      PullRequestHandler.pr_merge(repo, repository, token, opts)
    end)
  end

  @impl true
  def pr_checks(repo, opts \\ []) when is_map(repo) do
    with_repo_context(repo, opts, fn repository, token ->
      PullRequestHandler.pr_checks(repo, repository, token, opts)
    end)
  end

  @impl true
  def pr_issue_comments(repo, opts \\ []) when is_map(repo) do
    with_repo_context(repo, opts, fn repository, token ->
      ApiHandler.pr_issue_comments(repo, repository, token, opts)
    end)
  end

  @impl true
  def pr_add_issue_comment(repo, opts \\ []) when is_map(repo) do
    with_repo_context(repo, opts, fn repository, token ->
      ApiHandler.pr_add_issue_comment(repo, repository, token, opts)
    end)
  end

  @impl true
  def pr_reviews(repo, opts \\ []) when is_map(repo) do
    with_repo_context(repo, opts, fn repository, token ->
      ApiHandler.pr_reviews(repo, repository, token, opts)
    end)
  end

  @impl true
  def pr_review_comments(repo, opts \\ []) when is_map(repo) do
    with_repo_context(repo, opts, fn repository, token ->
      ApiHandler.pr_review_comments(repo, repository, token, opts)
    end)
  end

  @impl true
  def pr_reply_review_comment(repo, opts \\ []) when is_map(repo) do
    with_repo_context(repo, opts, fn repository, token ->
      ApiHandler.pr_reply_review_comment(repo, repository, token, opts)
    end)
  end

  # ── API Operations (delegated to ApiHandler) ─────────────────────

  @impl true
  def api(repo, opts \\ []) when is_map(repo) do
    with_token(opts, fn token ->
      ApiHandler.api(repo, token, opts)
    end)
  end

  # ── Run Operations (delegated to RunHandler) ─────────────────────

  @impl true
  def run_list(repo, opts \\ []) when is_map(repo) do
    with_repo_context(repo, opts, fn repository, token ->
      RunHandler.run_list(repo, repository, token, opts)
    end)
  end

  @impl true
  def run_view(repo, opts \\ []) when is_map(repo) do
    with_repo_context(repo, opts, fn repository, token ->
      RunHandler.run_view(repo, repository, token, opts)
    end)
  end

  # ── Lifecycle ────────────────────────────────────────────────────

  @impl true
  def close_open_pull_requests_for_branch(repo, branch, opts \\ [])
      when is_map(repo) and is_binary(branch) do
    with {:ok, token} <- access_token(opts),
         {:ok, repository} <- resolve_repository(repo, opts) do
      PullRequestHandler.close_open_pull_requests_for_branch(
        repo,
        repository,
        token,
        branch,
        opts
      )
    end
  end

  # ── Public: Repository Resolution ────────────────────────────────

  @spec resolve_repository(repo_config(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def resolve_repository(repo, opts \\ []) when is_map(repo) do
    case opts[:repo] || configured_repository(repo) || origin_repository_slug(repo, opts) do
      repository when is_binary(repository) and repository != "" ->
        {:ok, repository}

      _other ->
        {:error, :missing_cnb_repository_slug}
    end
  end

  @spec configured_repository(repo_config()) :: String.t() | nil
  def configured_repository(repo), do: RepoConfig.repository(repo)

  @spec parse_repository_slug(String.t()) :: String.t() | nil
  def parse_repository_slug(remote_url) when is_binary(remote_url) do
    remote_url
    |> String.trim()
    |> String.replace_suffix(".git", "")
    |> case do
      "" ->
        nil

      trimmed ->
        case Regex.run(~r{(?:^https?://|^git@)?cnb\.cool[:/](.+)$}, trimmed, capture: :all_but_first) do
          [path] ->
            path
            |> String.trim_leading("/")
            |> String.trim_trailing("/")
            |> normalize_repository_path()

          _ ->
            nil
        end
    end
  end

  # ── Private: Context Helpers ─────────────────────────────────────
  #
  # These two functions centralize the repeated token-acquisition and
  # repository-resolution logic that was previously inlined in every
  # callback. Both normalize all known CNB error atoms into structured
  # `%Error{}` values before returning.

  @spec with_repo_context(repo_config(), keyword(), (String.t(), String.t() -> term())) :: term()
  defp with_repo_context(repo, opts, fun) when is_map(repo) and is_function(fun, 2) do
    case access_token(opts) do
      {:ok, token} ->
        case resolve_repository(repo, opts) do
          {:ok, repository} ->
            fun.(repository, token) |> normalize_result()

          {:error, :missing_cnb_repository_slug} ->
            {:error,
             Error.runtime_failure(
               :missing_cnb_repository_slug,
               "CNB provider requires a repository slug"
             )}
        end

      {:error, :missing_cnb_token} ->
        {:error, Error.runtime_failure(:missing_cnb_token, "CNB provider requires CNB_TOKEN")}
    end
  end

  @spec with_token(keyword(), (String.t() -> term())) :: term()
  defp with_token(opts, fun) when is_function(fun, 1) do
    case access_token(opts) do
      {:ok, token} ->
        fun.(token) |> normalize_result()

      {:error, :missing_cnb_token} ->
        {:error, Error.runtime_failure(:missing_cnb_token, "CNB provider requires CNB_TOKEN")}
    end
  end

  # ── Private ──────────────────────────────────────────────────────

  defp normalize_result(:ok), do: :ok
  defp normalize_result({:ok, _value} = ok), do: ok
  defp normalize_result({:error, %Error{}} = error), do: error
  defp normalize_result({:error, reason}), do: {:error, Normalizer.map_runtime_error(reason)}

  defp access_token(opts), do: HttpClient.access_token(opts)

  defp origin_repository_slug(repo, opts) do
    context = RepoContext.new(repo, opts)

    case TargetRepo.remote_url(context.path, context.remote, opts) do
      {:ok, output} ->
        parse_repository_slug(output)

      {:error, _reason} ->
        nil
    end
  end

  defp normalize_repository_path(path) do
    segments =
      path
      |> String.split("/", trim: true)
      |> Enum.reject(&(&1 == ""))

    case segments do
      [_group, _repo | _rest] -> Enum.join(segments, "/")
      _other -> nil
    end
  end
end
