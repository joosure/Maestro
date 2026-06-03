defmodule SymphonyElixir.RepoProvider.Memory do
  @moduledoc """
  In-memory repo-provider adapter used for tests and local development.

  Stores state via `Application.get_env/3` so tests can inject
  predetermined PR views, check results, and other responses without
  any external tooling or network access.

  ## Test Usage

      setup do
        Application.put_env(:symphony_elixir, :repo_provider_adapters, %{
          "memory" => SymphonyElixir.RepoProvider.Memory
        })
        Application.put_env(:symphony_elixir, :memory_repo_provider_pr, %{
          "url" => "https://example.com/pr/1",
          "state" => "OPEN",
          "title" => "Test PR"
        })
        on_exit(fn ->
          Application.delete_env(:symphony_elixir, :repo_provider_adapters)
          Application.delete_env(:symphony_elixir, :memory_repo_provider_pr)
        end)
      end
  """

  @behaviour SymphonyElixir.RepoProvider.Adapter

  alias SymphonyElixir.RepoProvider.ConfigValidator
  alias SymphonyElixir.RepoProvider.Kinds

  # ── Required ─────────────────────────────────────────────────────
  @capabilities SymphonyElixir.RepoProvider.Adapter.all_capabilities()
  @provider_kind Kinds.memory()

  @impl true
  @spec kind() :: String.t()
  def kind, do: @provider_kind

  @impl true
  @spec defaults() :: map()
  def defaults, do: %{}

  @impl true
  @spec validate_config(map()) :: :ok | {:error, term()}
  def validate_config(repo), do: ConfigValidator.validate(repo, __MODULE__)

  @impl true
  def capabilities, do: @capabilities

  @impl true
  def supported_config_options, do: [:required_pr_label, :change_proposal_body_generator]

  # ── PR operations ────────────────────────────────────────────────

  @impl true
  def auth_status(_repo, _opts \\ []) do
    {:ok, "memory auth ok"}
  end

  @impl true
  def pr_view(_repo, _opts \\ []) do
    case Application.get_env(:symphony_elixir, :memory_repo_provider_pr) do
      nil -> {:error, {:memory_pr_not_configured, "No PR configured for memory adapter"}}
      pr when is_map(pr) -> {:ok, pr}
    end
  end

  @impl true
  def pr_create(_repo, opts \\ []) do
    send_event({:memory_repo_provider_pr_create, opts})
    {:ok, "https://example.com/pr/new"}
  end

  @impl true
  def pr_edit(_repo, opts \\ []) do
    send_event({:memory_repo_provider_pr_edit, opts})
    {:ok, "https://example.com/pr/1"}
  end

  @impl true
  def pr_add_label(_repo, opts \\ []) do
    send_event({:memory_repo_provider_pr_add_label, opts})
    {:ok, "https://example.com/pr/1"}
  end

  @impl true
  def pr_issue_comments(_repo, _opts \\ []) do
    comments = Application.get_env(:symphony_elixir, :memory_repo_provider_issue_comments, [])
    {:ok, comments}
  end

  @impl true
  def pr_add_issue_comment(_repo, opts \\ []) do
    send_event({:memory_repo_provider_pr_add_issue_comment, opts})

    {:ok,
     %{
       "id" => 1_000,
       "body" => opts[:body] || "",
       "user" => %{"login" => "memory", "type" => "User"}
     }}
  end

  @impl true
  def pr_reviews(_repo, _opts \\ []) do
    reviews = Application.get_env(:symphony_elixir, :memory_repo_provider_reviews, [])
    {:ok, reviews}
  end

  @impl true
  def pr_submit_review(_repo, opts \\ []) do
    send_event({:memory_repo_provider_pr_submit_review, opts})

    {:ok,
     %{
       "id" => 1_002,
       "body" => opts[:body] || "",
       "state" => opts[:event] || "comment",
       "user" => %{"login" => "memory", "type" => "User"}
     }}
  end

  @impl true
  def pr_review_comments(_repo, _opts \\ []) do
    comments = Application.get_env(:symphony_elixir, :memory_repo_provider_review_comments, [])
    {:ok, comments}
  end

  @impl true
  def pr_reply_review_comment(_repo, opts \\ []) do
    send_event({:memory_repo_provider_pr_reply_review_comment, opts})

    {:ok,
     %{
       "id" => 1_001,
       "body" => opts[:body] || "",
       "in_reply_to_id" => opts[:comment_id],
       "user" => %{"login" => "memory", "type" => "User"}
     }}
  end

  @impl true
  def pr_close(_repo, opts \\ []) do
    send_event({:memory_repo_provider_pr_close, opts})
    {:ok, "https://example.com/pr/1"}
  end

  @impl true
  def pr_merge(_repo, opts \\ []) do
    send_event({:memory_repo_provider_pr_merge, opts})
    {:ok, "https://example.com/pr/1"}
  end

  @impl true
  def pr_checks(_repo, _opts \\ []) do
    checks = Application.get_env(:symphony_elixir, :memory_repo_change_proposal_checks, [])
    {:ok, checks}
  end

  # ── API & CI ─────────────────────────────────────────────────────

  @impl true
  def api(_repo, _opts \\ []) do
    case Application.get_env(:symphony_elixir, :memory_repo_provider_api_response) do
      nil -> {:ok, %{}}
      response -> {:ok, response}
    end
  end

  @impl true
  def run_list(_repo, _opts \\ []) do
    runs = Application.get_env(:symphony_elixir, :memory_repo_provider_runs, [])
    {:ok, runs}
  end

  @impl true
  def run_view(_repo, _opts \\ []) do
    case Application.get_env(:symphony_elixir, :memory_repo_provider_run) do
      nil -> {:error, {:memory_run_not_configured, "No run configured for memory adapter"}}
      run -> {:ok, run}
    end
  end

  # ── Lifecycle ────────────────────────────────────────────────────

  @impl true
  def close_open_pull_requests_for_branch(_repo, branch, _opts \\ []) do
    send_event({:memory_repo_provider_close_prs, branch})
    :ok
  end

  # ── Healthcheck ───────────────────────────────────────────────────

  @impl true
  def healthcheck(_repo, _opts \\ []), do: :ok

  # ── Private ──────────────────────────────────────────────────────

  defp send_event(message) do
    case Application.get_env(:symphony_elixir, :memory_repo_provider_recipient) do
      pid when is_pid(pid) -> send(pid, message)
      _ -> :ok
    end
  end
end
