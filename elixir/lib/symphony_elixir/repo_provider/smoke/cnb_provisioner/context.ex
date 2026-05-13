defmodule SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.Context do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Config, as: RepoConfig
  alias SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.{Runtime, Settings}
  alias SymphonyElixir.RepoProvider.Smoke.ProbeRunner

  @spec needs_base_resolution?(keyword(), map()) :: boolean()
  def needs_base_resolution?(opts, repo_config) do
    is_nil(ProbeRunner.blank_to_nil(Keyword.get(opts, :base))) and
      is_nil(ProbeRunner.blank_to_nil(Map.get(repo_config, :base_branch)))
  end

  @spec build(keyword(), map(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  def build(opts, repo_config, env_map, deps) do
    repository = ProbeRunner.blank_to_nil(Map.get(env_map, "SYMPHONY_REPO_PROVIDER_REPOSITORY"))
    token = ProbeRunner.blank_to_nil(Map.get(env_map, "CNB_TOKEN"))
    base = ProbeRunner.blank_to_nil(Keyword.get(opts, :base)) || ProbeRunner.blank_to_nil(Map.get(repo_config, :base_branch))
    head = "#{Settings.branch_prefix()}-#{System.unique_integer([:positive, :monotonic])}"

    cond do
      is_nil(repository) ->
        {:error, "CNB auto-provision smoke requires --repo or SYMPHONY_REPO_PROVIDER_REPOSITORY"}

      is_nil(token) ->
        {:error, "CNB auto-provision smoke requires CNB_TOKEN"}

      true ->
        case Runtime.mk_temp_dir(deps, "repo-provider-cnb-smoke") do
          {:ok, temp_dir} ->
            {:ok,
             %{
               repository: repository,
               token: token,
               clone_url: cnb_clone_url(repo_config, repository),
               temp_dir: temp_dir,
               worktree: Path.join(temp_dir, "repo"),
               base: base,
               head: head,
               title_override: ProbeRunner.blank_to_nil(Keyword.get(opts, :title)),
               body_override: ProbeRunner.blank_to_nil(Keyword.get(opts, :body)),
               title: nil,
               body: nil,
               edited_body: nil,
               remote_branch?: false,
               pr_number: nil,
               pr_url: nil
             }}

          {:error, reason} ->
            {:error, "Failed to create a temporary worktree for CNB smoke: #{inspect(reason)}"}
        end
    end
  end

  @spec finalize(map()) :: map()
  def finalize(context) do
    body =
      context.body_override ||
        "Created by Symphony repo-provider destructive smoke.\n\nMode: auto-provision-cnb-pipeline\nHead: #{context.head}\nBase: #{context.base}"

    title =
      context.title_override ||
        "Repo-provider CNB auto-provision smoke for #{context.head} -> #{context.base}"

    %{context | title: title, body: body}
  end

  defp cnb_clone_url(repo_config, repository) do
    case RepoConfig.web_base_url(repo_config) do
      web_base_url when is_binary(web_base_url) and web_base_url != "" ->
        "#{String.trim_trailing(web_base_url, "/")}/#{repository}.git"

      _other ->
        "#{String.trim_trailing(Settings.default_web_base_url(), "/")}/#{repository}.git"
    end
  end
end
