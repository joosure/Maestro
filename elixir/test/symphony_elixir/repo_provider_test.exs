defmodule SymphonyElixir.RepoProviderTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.RepoProvider.CNB
  alias SymphonyElixir.RepoProvider.Config, as: RepoConfig
  alias SymphonyElixir.RepoProvider.ConfigValidator
  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.GitHub
  alias SymphonyElixir.RepoProvider.Memory
  alias SymphonyElixir.RepoProvider.RuntimeConfig
  alias SymphonyElixir.Workflow

  test "supports known provider kinds and adapter lookup" do
    assert Enum.sort(RepoProvider.supported_kinds()) == ["cnb", "github", "memory"]
    assert RepoProvider.adapter_for("cnb") == CNB.Adapter
    assert RepoProvider.adapter_for("github") == GitHub.Adapter
    assert RepoProvider.adapter_for("gitlab") == nil
    assert RepoProvider.adapter_for(:github) == nil
    assert RepoProvider.default_kind() == "github"
  end

  test "reads current provider kind from config and uses github as the default" do
    assert RepoProvider.current_kind(%{provider: %{kind: "cnb"}}) == "cnb"
    assert RepoProvider.current_kind(%{provider: %{kind: ""}}) == "github"
    assert RepoProvider.current_kind(%{}) == "github"

    write_workflow_file!(Workflow.workflow_file_path(),
      repo_provider_kind: "cnb",
      repo_provider_repository: "acme/widgets",
      repo_provider_api_base_url: "https://api.cnb.example.test",
      repo_provider_web_base_url: "https://cnb.example.test"
    )

    assert RepoProvider.current_kind() == "cnb"
  end

  test "validates provider config and rejects unsupported kinds" do
    assert :ok == RepoProvider.validate_config(%{provider: %{kind: "github"}})
    assert :ok == RepoProvider.validate_config(%{provider: %{kind: "cnb"}})

    assert {:error, %Error{code: :unsupported_provider, provider: "gitlab", operation: :validate_config}} =
             RepoProvider.validate_config(%{provider: %{kind: "gitlab"}})

    assert {:error, %Error{code: :unsupported_provider, provider: "unknown", operation: :validate_config}} =
             RepoProvider.validate_config(:invalid)
  end

  test "repo config reads required PR label from provider options" do
    assert RepoConfig.option(
             %{provider: %{options: %{"required_pr_label" => "release-ready"}}},
             "required_pr_label"
           ) ==
             "release-ready"

    assert RepoConfig.required_pr_label(%{
             provider: %{options: %{"required_pr_label" => "release-ready"}}
           }) ==
             "release-ready"
  end

  test "repo config reads configured change proposal body generator from provider options" do
    generator = %{"kind" => "template", "template" => "{{ title }}"}

    assert RepoConfig.change_proposal_body_generator(%{
             provider: %{options: %{"change_proposal_body_generator" => generator}}
           }) == generator
  end

  test "repo config accessors read provider and runtime values from string-key maps" do
    repo = %{
      "provider" => %{
        "kind" => "cnb",
        "repository" => "acme/widgets",
        "api_base_url" => "https://api.cnb.example.test"
      },
      "runtime" => %{
        "http_timeout_seconds" => "12"
      }
    }

    assert RepoConfig.kind(repo) == "cnb"
    assert RepoConfig.repository(repo) == "acme/widgets"
    assert RepoConfig.provider_value(repo, "api_base_url") == "https://api.cnb.example.test"
    assert RepoConfig.runtime_value(repo, "http_timeout_seconds") == "12"
  end

  test "shared repo-provider config validator uses adapter-declared supported options" do
    github_repo = %{provider: %{kind: "github", options: %{required_pr_label: "release-ready"}}}
    cnb_repo = %{provider: %{kind: "cnb", options: %{required_pr_label: "release-ready"}}}

    assert ConfigValidator.supported_config_options(GitHub.Adapter) == [
             :required_pr_label,
             :change_proposal_body_generator
           ]

    assert ConfigValidator.supported_config_options(CNB.Adapter) == [
             :change_proposal_body_generator
           ]

    assert ConfigValidator.supported_config_options(Memory) == [
             :required_pr_label,
             :change_proposal_body_generator
           ]

    assert :ok == ConfigValidator.validate(github_repo, GitHub.Adapter)
    assert :ok == ConfigValidator.validate(github_repo, Memory)

    assert {:error,
            %Error{
              code: :unsupported_option,
              provider: "cnb",
              operation: :validate_config
            }} = ConfigValidator.validate(cnb_repo, CNB.Adapter)

    invalid_generator_repo = %{
      provider: %{
        kind: "github",
        options: %{change_proposal_body_generator: %{kind: "template", template: "{{ unknown }}"}}
      }
    }

    assert {:error,
            %Error{
              code: :invalid_option,
              provider: "github",
              operation: :validate_config
            }} = ConfigValidator.validate(invalid_generator_repo, GitHub.Adapter)
  end

  test "repo-provider exposes explicit capabilities per adapter" do
    all_capabilities = SymphonyElixir.RepoProvider.Adapter.all_capabilities()
    cnb_capabilities = all_capabilities -- [:pr_add_label, :pr_submit_review]

    assert RepoProvider.capabilities(%{provider: %{kind: "github"}}) == all_capabilities
    assert RepoProvider.capabilities(%{provider: %{kind: "cnb"}}) == cnb_capabilities
    assert RepoProvider.capabilities(%{provider: %{kind: "memory"}}) == all_capabilities
    assert RepoProvider.capabilities(%{provider: %{kind: "gitlab"}}) == []

    assert RepoProvider.supports?(%{provider: %{kind: "github"}}, :pr_view)
    assert RepoProvider.supports?(%{provider: %{kind: "github"}}, :pr_submit_review)
    assert RepoProvider.supports?(%{provider: %{kind: "cnb"}}, :healthcheck)
    refute RepoProvider.supports?(%{provider: %{kind: "cnb"}}, :pr_add_label)
    refute RepoProvider.supports?(%{provider: %{kind: "cnb"}}, :pr_submit_review)
    refute RepoProvider.supports?(%{provider: %{kind: "gitlab"}}, :pr_view)
  end

  test "builds runtime env and omits blank provider values" do
    assert RepoProvider.runtime_env(%{}) == [{"SYMPHONY_REPO_PROVIDER_KIND", "github"}]

    assert RepoProvider.runtime_env(%{
             provider: %{
               kind: "cnb",
               repository: "acme/widgets",
               api_base_url: "",
               web_base_url: nil
             }
           }) == [
             {"SYMPHONY_REPO_PROVIDER_KIND", "cnb"},
             {"SYMPHONY_REPO_PROVIDER_REPOSITORY", "acme/widgets"}
           ]

    assert RepoProvider.runtime_env(%{
             path: "source",
             base_branch: "trunk",
             remote: %{name: "upstream", url: "https://example.test/acme/widgets.git"},
             branch: %{work_prefix: "ticket/work"},
             provider: %{kind: "github"}
           }) == [
             {"SYMPHONY_REPO_PATH", "source"},
             {"SYMPHONY_REPO_REMOTE", "upstream"},
             {"SYMPHONY_REPO_REMOTE_URL", "https://example.test/acme/widgets.git"},
             {"SYMPHONY_REPO_BASE_BRANCH", "trunk"},
             {"SYMPHONY_REPO_BRANCH_WORK_PREFIX", "ticket/work"},
             {"SYMPHONY_REPO_PROVIDER_KIND", "github"}
           ]

    assert RepoProvider.runtime_env(:invalid) == [{"SYMPHONY_REPO_PROVIDER_KIND", "github"}]

    write_workflow_file!(Workflow.workflow_file_path(),
      repo_provider_kind: "cnb",
      repo_provider_repository: "acme/widgets",
      repo_provider_api_base_url: "https://api.cnb.example.test",
      repo_provider_web_base_url: "https://cnb.example.test"
    )

    assert RepoProvider.runtime_env() == [
             {"SYMPHONY_REPO_PATH", "repo"},
             {"SYMPHONY_REPO_REMOTE", "origin"},
             {"SYMPHONY_REPO_BASE_BRANCH", "main"},
             {"SYMPHONY_REPO_PROVIDER_KIND", "cnb"},
             {"SYMPHONY_REPO_PROVIDER_REPOSITORY", "acme/widgets"},
             {"SYMPHONY_REPO_PROVIDER_API_BASE_URL", "https://api.cnb.example.test"},
             {"SYMPHONY_REPO_PROVIDER_WEB_BASE_URL", "https://cnb.example.test"}
           ]
  end

  test "repo-provider runtime config accepts SOURCE_REPO workflow env aliases" do
    config =
      RuntimeConfig.from_env(%{
        "SOURCE_REPO_BASE_BRANCH" => "main",
        "SOURCE_REPO_URL" => "https://cnb.cool/acme/widgets",
        "SOURCE_REPO_PROVIDER_KIND" => "cnb",
        "SOURCE_REPO_PROVIDER_REPOSITORY" => "acme/widgets"
      })

    assert RepoConfig.base_branch(config) == "main"
    assert RepoConfig.remote_url(config) == "https://cnb.cool/acme/widgets"
    assert RepoConfig.kind(config) == "cnb"
    assert RepoConfig.repository(config) == "acme/widgets"
  end

  test "delegates close operations and handles nil or unsupported branches" do
    assert :ok == RepoProvider.close_open_pull_requests_for_branch(%{}, nil)

    assert {:error, %Error{code: :unsupported_provider, provider: "gitlab"}} =
             RepoProvider.close_open_pull_requests_for_branch(
               %{provider: %{kind: "gitlab"}},
               "feature/unsupported"
             )

    assert {:error,
            %Error{
              code: :missing_cnb_token,
              provider: "cnb",
              operation: :close_open_pull_requests_for_branch
            }} =
             RepoProvider.close_open_pull_requests_for_branch(
               %{provider: %{kind: "cnb", repository: "acme/widgets"}},
               "feature/cnb-provider",
               token: nil
             )

    assert :ok ==
             RepoProvider.close_open_pull_requests_for_branch(
               %{provider: %{kind: "github", repository: "acme/widgets"}},
               "feature/github-provider",
               find_executable: fn "gh" -> nil end
             )
  end
end
