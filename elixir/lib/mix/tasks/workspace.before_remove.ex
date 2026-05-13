defmodule Mix.Tasks.Workspace.BeforeRemove do
  use Mix.Task

  alias SymphonyElixir.{Config, RepoProvider}
  alias SymphonyElixir.Repo, as: TargetRepo
  alias SymphonyElixir.Repo.Context, as: RepoContext
  alias SymphonyElixir.RepoProvider.Error

  @shortdoc "Close open provider-backed PRs for the current branch before workspace removal"

  @moduledoc """
  Closes open pull requests for the current Git branch through the active repo
  provider.

  This task is intended for use from the `before_remove` workspace hook.

  Usage:

      mix workspace.before_remove
      mix workspace.before_remove --branch feature/my-branch
      mix workspace.before_remove --provider github
      mix workspace.before_remove --repo owner/repo
  """

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [branch: :string, help: :boolean, provider: :string, repo: :string],
        aliases: [h: :help]
      )

    cond do
      opts[:help] ->
        Mix.shell().info(@moduledoc)

      invalid != [] ->
        Mix.raise("Invalid option(s): #{inspect(invalid)}")

      true ->
        repo_config = repo_config(opts)
        branch = opts[:branch] || current_branch(repo_config)

        maybe_close_open_pull_requests(repo_config, branch, opts)
    end
  end

  defp maybe_close_open_pull_requests(_repo_config, nil, _opts), do: :ok

  defp maybe_close_open_pull_requests(repo_config, branch, opts) do
    case RepoProvider.close_open_pull_requests_for_branch(repo_config, branch, repo: opts[:repo]) do
      :ok ->
        :ok

      {:error, %Error{code: :unsupported_provider, provider: kind}} ->
        Mix.shell().error("Unsupported repo provider kind: #{inspect(kind)}. Supported: #{inspect(RepoProvider.supported_kinds())}")

        :ok

      {:error, reason} ->
        Mix.shell().error("Failed to close PRs for branch #{branch}: #{format_error(reason)}")
        :ok
    end
  end

  defp format_error(%Error{message: message}) when is_binary(message) and message != "", do: message
  defp format_error(reason), do: inspect(reason)

  defp repo_config(opts) do
    configured_repo = configured_repo_config()
    configured_provider = Map.get(configured_repo, :provider) || %{}

    provider =
      configured_provider
      |> Map.put(
        :kind,
        opts[:provider] ||
          Map.get(configured_provider, :kind) ||
          RepoProvider.default_kind()
      )
      |> Map.put(:repository, opts[:repo] || Map.get(configured_provider, :repository))

    Map.put(configured_repo, :provider, provider)
  end

  defp configured_repo_config do
    case Config.settings() do
      {:ok, settings} ->
        settings.repo
        |> Map.from_struct()
        |> maybe_drop_missing_default_path()

      {:error, _reason} ->
        %{}
    end
  end

  defp maybe_drop_missing_default_path(%{path: "repo"} = repo_config) do
    if File.dir?("repo"), do: repo_config, else: Map.delete(repo_config, :path)
  end

  defp maybe_drop_missing_default_path(repo_config), do: repo_config

  defp current_branch(repo_config) do
    case TargetRepo.current_branch(RepoContext.path(repo_config)) do
      {:ok, branch} ->
        branch

      {:error, _reason} ->
        nil
    end
  end
end
