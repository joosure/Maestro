defmodule SymphonyElixir.RepoProvider.RuntimeConfigTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.RepoProvider.Config
  alias SymphonyElixir.RepoProvider.RuntimeConfig

  test "infers provider repository from SOURCE_REPO_URL when repository env is absent" do
    config =
      RuntimeConfig.from_env(%{
        "SOURCE_REPO_URL" => "https://github.com/acme/widgets.git",
        "SOURCE_REPO_PROVIDER_KIND" => "github"
      })

    assert Config.repository(config) == "acme/widgets"
  end

  test "explicit provider repository env wins over inferred repository" do
    config =
      RuntimeConfig.from_env(%{
        "SOURCE_REPO_URL" => "https://github.com/acme/widgets.git",
        "SOURCE_REPO_PROVIDER_REPOSITORY" => "override/repo"
      })

    assert Config.repository(config) == "override/repo"
  end
end
