defmodule SymphonyElixir.RepoProviderRegistryTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.RepoProvider.Error

  defmodule FakeAdapter do
    @behaviour SymphonyElixir.RepoProvider.Adapter

    def kind, do: "fake"
    def defaults, do: %{}
    def validate_config(_repo), do: :ok
    def capabilities, do: [:auth_status, :pr_view, :close_open_pull_requests_for_branch]

    def auth_status(_repo, _opts \\ []) do
      send(self(), :fake_auth_status_called)
      {:ok, "fake auth ok"}
    end

    def pr_view(_repo, opts \\ []) do
      send(self(), {:fake_pr_view_called, opts})
      {:ok, %{"url" => "https://example.test/pr/#{opts[:number] || "current"}"}}
    end

    def close_open_pull_requests_for_branch(_repo, branch, _opts \\ []) do
      send(self(), {:fake_close_branch_called, branch})
      :ok
    end
  end

  defmodule FakeCoreAdapter do
    @behaviour SymphonyElixir.RepoProvider.Adapter

    def kind, do: "fake_core"
    def defaults, do: %{}
    def validate_config(_repo), do: :ok
    def capabilities, do: []
  end

  defmodule FakeErrorAdapter do
    @behaviour SymphonyElixir.RepoProvider.Adapter

    def kind, do: "fake_error"
    def defaults, do: %{}
    def validate_config(_repo), do: :ok
    def capabilities, do: [:pr_view, :close_open_pull_requests_for_branch]
    def pr_view(_repo, _opts \\ []), do: {:error, :fake_view_failed}

    def close_open_pull_requests_for_branch(_repo, _branch, _opts \\ []),
      do: {:error, {:fake_close_failed, :denied}}
  end

  defmodule FakeBrokenCapabilityAdapter do
    @behaviour SymphonyElixir.RepoProvider.Adapter

    def kind, do: "fake_broken"
    def defaults, do: %{}
    def validate_config(_repo), do: :ok
    def capabilities, do: [:auth_status]
  end

  test "registry merges configured adapters and facade delegates to the configured provider adapter" do
    Application.put_env(:symphony_elixir, :repo_provider_adapters, %{"fake" => FakeAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :repo_provider_adapters)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      repo_provider_kind: "fake",
      repo_provider_repository: "acme/widgets",
      repo_provider_api_base_url: "https://api.fake.example.test",
      repo_provider_web_base_url: "https://fake.example.test"
    )

    assert RepoProvider.supported_kinds() |> Enum.sort() == ["cnb", "fake", "github", "memory"]
    assert RepoProvider.adapter() == FakeAdapter
    assert RepoProvider.adapter_for("fake") == FakeAdapter
    assert RepoProvider.current_kind() == "fake"
    assert %RepoProvider.Config{} = RepoProvider.Config.current!()

    assert {:ok, "fake auth ok"} = RepoProvider.auth_status()
    assert_received :fake_auth_status_called

    assert {:ok, %{"url" => "https://example.test/pr/42"}} =
             RepoProvider.pr_view(number: "42")

    assert_received {:fake_pr_view_called, [number: "42"]}

    assert :ok ==
             RepoProvider.close_open_pull_requests_for_branch(
               %{provider: %{kind: "fake"}},
               "feature/fake-provider"
             )

    assert_received {:fake_close_branch_called, "feature/fake-provider"}
  end

  test "repo-provider facade exposes safe defaults for unsupported optional capabilities" do
    Application.put_env(:symphony_elixir, :repo_provider_adapters, %{
      "fake_core" => FakeCoreAdapter
    })

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :repo_provider_adapters)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      repo_provider_kind: "fake_core",
      repo_provider_repository: "acme/widgets",
      repo_provider_api_base_url: nil,
      repo_provider_web_base_url: nil
    )

    assert RepoProvider.adapter() == FakeCoreAdapter

    assert {:error,
            %Error{
              code: :unsupported_capability,
              provider: "fake_core",
              operation: :auth_status
            }} = RepoProvider.auth_status()

    assert {:error,
            %Error{
              code: :unsupported_capability,
              provider: "fake_core",
              operation: :pr_add_label
            }} = RepoProvider.pr_add_label(label: "release-ready")

    assert {:error,
            %Error{
              code: :unsupported_capability,
              provider: "fake_core",
              operation: :pr_issue_comments
            }} = RepoProvider.pr_issue_comments()

    assert {:error,
            %Error{
              code: :unsupported_capability,
              provider: "fake_core",
              operation: :pr_add_issue_comment
            }} = RepoProvider.pr_add_issue_comment(body: "[codex] acknowledged")

    assert {:error,
            %Error{
              code: :unsupported_capability,
              provider: "fake_core",
              operation: :pr_reviews
            }} = RepoProvider.pr_reviews()

    assert {:error,
            %Error{
              code: :unsupported_capability,
              provider: "fake_core",
              operation: :pr_submit_review
            }} = RepoProvider.pr_submit_review(event: "comment", body: "[codex] review note")

    assert {:error,
            %Error{
              code: :unsupported_capability,
              provider: "fake_core",
              operation: :pr_review_comments
            }} = RepoProvider.pr_review_comments()

    assert {:error,
            %Error{
              code: :unsupported_capability,
              provider: "fake_core",
              operation: :pr_reply_review_comment
            }} =
             RepoProvider.pr_reply_review_comment(comment_id: "101", body: "[codex] acknowledged")

    assert :ok ==
             RepoProvider.close_open_pull_requests_for_branch(
               %{provider: %{kind: "fake_core"}},
               "feature/no-op-close"
             )
  end

  test "repo-provider facade surfaces invalid adapter capability declarations" do
    Application.put_env(:symphony_elixir, :repo_provider_adapters, %{
      "fake_broken" => FakeBrokenCapabilityAdapter
    })

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :repo_provider_adapters)
    end)

    repo = %{provider: %{kind: "fake_broken", repository: "acme/widgets"}}

    assert {:error,
            %Error{
              code: :invalid_adapter_capability,
              provider: "fake_broken",
              operation: :auth_status,
              details: %{adapter: FakeBrokenCapabilityAdapter, capability: :auth_status}
            }} = RepoProvider.auth_status(repo)
  end

  test "repo-provider facade normalizes adapter runtime errors into structured errors" do
    Application.put_env(:symphony_elixir, :repo_provider_adapters, %{
      "fake_error" => FakeErrorAdapter
    })

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :repo_provider_adapters)
    end)

    repo = %{provider: %{kind: "fake_error", repository: "acme/widgets"}}

    assert {:error,
            %Error{
              code: :fake_view_failed,
              provider: "fake_error",
              operation: :pr_view,
              details: %{source_reason: :fake_view_failed}
            }} = RepoProvider.pr_view(repo)

    assert {:error,
            %Error{
              code: :fake_close_failed,
              provider: "fake_error",
              operation: :close_open_pull_requests_for_branch,
              details: %{source_reason: {:fake_close_failed, :denied}}
            }} =
             RepoProvider.close_open_pull_requests_for_branch(
               repo,
               "feature/fake-error"
             )
  end
end
