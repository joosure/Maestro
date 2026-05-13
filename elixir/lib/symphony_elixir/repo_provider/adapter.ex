defmodule SymphonyElixir.RepoProvider.Adapter do
  @moduledoc """
  Unified repo-provider adapter contract.

  Defines the behaviour that all repository provider integrations
  must implement. The facade (`SymphonyElixir.RepoProvider`) dispatches
  to whichever adapter the current provider `kind` resolves to via
  the `Registry`.

  ## Required Callbacks

    * `kind/0` — unique string identifier (e.g. `"cnb"`, `"github"`)
    * `defaults/0` — provider-owned defaults for config finalization. Adapters
      may return nested `provider`, `runtime`, and `env_vars` maps. The
      finalizer treats unknown keys as adapter-owned opaque configuration.
    * `validate_config/1` — fail-fast configuration validation; returns
      `:ok` or `{:error, term()}`. Built-in adapters delegate shared
      shared option support checks to `RepoProvider.ConfigValidator`.
    * `capabilities/0` — explicit list of optional operations implemented by
      the adapter. The facade uses this declaration for dispatch instead of
      inferring support from exported functions alone.

  ## Optional Callbacks

  All remaining callbacks are optional. Adapters must list supported
  operations in `capabilities/0`; undeclared callbacks are treated as
  unsupported by the facade, even if a function happens to exist.

    * `supported_config_options/0` — shared canonical options accepted by
      the adapter (for example required PR labels or change-proposal body
      generators)

  ## Implementing a New Adapter

      defmodule MyApp.RepoProvider.GitLab.Adapter do
        @behaviour SymphonyElixir.RepoProvider.Adapter

        def kind, do: "gitlab"
        def defaults, do: %{}
        def validate_config(_repo), do: :ok
        def capabilities, do: [:auth_status, :pr_view]
        # implement optional callbacks as needed …
      end

  Register at runtime:

      config :symphony_elixir, :repo_provider_adapters, %{
        "gitlab" => MyApp.RepoProvider.GitLab.Adapter
      }
  """

  alias SymphonyElixir.RepoProvider.{Config, Error}

  @type result(t) :: {:ok, t} | {:error, Error.t() | term()}
  @type capability ::
          :auth_status
          | :pr_view
          | :pr_create
          | :pr_edit
          | :pr_add_label
          | :pr_issue_comments
          | :pr_add_issue_comment
          | :pr_reviews
          | :pr_submit_review
          | :pr_review_comments
          | :pr_reply_review_comment
          | :pr_close
          | :pr_merge
          | :pr_checks
          | :api
          | :run_list
          | :run_view
          | :close_open_pull_requests_for_branch
          | :healthcheck

  @capability_callbacks %{
    auth_status: 2,
    pr_view: 2,
    pr_create: 2,
    pr_edit: 2,
    pr_add_label: 2,
    pr_issue_comments: 2,
    pr_add_issue_comment: 2,
    pr_reviews: 2,
    pr_submit_review: 2,
    pr_review_comments: 2,
    pr_reply_review_comment: 2,
    pr_close: 2,
    pr_merge: 2,
    pr_checks: 2,
    api: 2,
    run_list: 2,
    run_view: 2,
    close_open_pull_requests_for_branch: 3,
    healthcheck: 2
  }
  @all_capabilities Map.keys(@capability_callbacks)

  # ── Required ─────────────────────────────────────────────────────

  @callback kind() :: String.t()
  @callback defaults() :: map()
  @callback validate_config(Config.t()) :: :ok | {:error, Error.t() | term()}
  @callback capabilities() :: [capability()]
  @callback supported_config_options() :: [atom()]

  # ── PR operations ────────────────────────────────────────────────

  @callback auth_status(Config.t(), keyword()) :: result(String.t())
  @callback pr_view(Config.t(), keyword()) :: result(map())
  @callback pr_create(Config.t(), keyword()) :: result(String.t())
  @callback pr_edit(Config.t(), keyword()) :: result(String.t())
  @callback pr_add_label(Config.t(), keyword()) :: result(String.t())
  @callback pr_issue_comments(Config.t(), keyword()) :: result(list(map()))
  @callback pr_add_issue_comment(Config.t(), keyword()) :: result(map())
  @callback pr_reviews(Config.t(), keyword()) :: result(list(map()))
  @callback pr_submit_review(Config.t(), keyword()) :: result(map())
  @callback pr_review_comments(Config.t(), keyword()) :: result(list(map()))
  @callback pr_reply_review_comment(Config.t(), keyword()) :: result(map())
  @callback pr_close(Config.t(), keyword()) :: result(String.t())
  @callback pr_merge(Config.t(), keyword()) :: result(String.t())
  @callback pr_checks(Config.t(), keyword()) :: result(list(map()))

  # ── API & CI ─────────────────────────────────────────────────────

  @callback api(Config.t(), keyword()) :: result(term())
  @callback run_list(Config.t(), keyword()) :: result(list(map()))
  @callback run_view(Config.t(), keyword()) :: result(map() | String.t())

  # ── Lifecycle ────────────────────────────────────────────────────

  @callback close_open_pull_requests_for_branch(Config.t(), String.t(), keyword()) ::
              :ok | {:error, Error.t() | term()}
  @callback healthcheck(Config.t(), keyword()) :: :ok | {:error, Error.t() | term()}

  @spec capability_callbacks() :: %{capability() => pos_integer()}
  def capability_callbacks, do: @capability_callbacks

  @spec all_capabilities() :: [capability()]
  def all_capabilities, do: @all_capabilities

  @optional_callbacks [
    supported_config_options: 0,
    auth_status: 2,
    pr_view: 2,
    pr_create: 2,
    pr_edit: 2,
    pr_add_label: 2,
    pr_issue_comments: 2,
    pr_add_issue_comment: 2,
    pr_reviews: 2,
    pr_submit_review: 2,
    pr_review_comments: 2,
    pr_reply_review_comment: 2,
    pr_close: 2,
    pr_merge: 2,
    pr_checks: 2,
    api: 2,
    run_list: 2,
    run_view: 2,
    close_open_pull_requests_for_branch: 3,
    healthcheck: 2
  ]
end
