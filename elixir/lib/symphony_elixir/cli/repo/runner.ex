defmodule SymphonyElixir.CLI.Repo.Runner do
  @moduledoc false

  alias SymphonyElixir.CLI.Repo.Options, as: RepoOptions
  alias SymphonyElixir.CLI.Repo.Renderer
  alias SymphonyElixir.Repo

  @type output :: {String.t(), String.t(), non_neg_integer()}

  @spec run(String.t(), [String.t()], RepoOptions.repo_opts(), keyword(), keyword()) :: output()
  def run("root", _args, opts, _cli_opts, command_opts) do
    opts
    |> RepoOptions.path()
    |> Repo.root(command_opts)
    |> Renderer.scalar()
  end

  def run("current-branch", _args, opts, _cli_opts, command_opts) do
    opts
    |> RepoOptions.path()
    |> Repo.current_branch(command_opts)
    |> Renderer.scalar()
  end

  def run("head-sha", _args, opts, _cli_opts, command_opts) do
    opts
    |> RepoOptions.path()
    |> Repo.head_sha(command_opts)
    |> Renderer.scalar()
  end

  def run("published-head-sha", [branch], opts, _cli_opts, command_opts) do
    Repo.published_head_sha(RepoOptions.path(opts), RepoOptions.remote(opts), branch, command_opts)
    |> Renderer.scalar()
  end

  def run("remote-url", _args, opts, _cli_opts, command_opts) do
    Repo.remote_url(RepoOptions.path(opts), RepoOptions.remote(opts), command_opts)
    |> Renderer.scalar()
  end

  def run("base-branch", _args, opts, _cli_opts, command_opts) do
    repo_opts =
      command_opts
      |> Keyword.merge(path: RepoOptions.path(opts), remote: RepoOptions.remote(opts))
      |> maybe_put(:base_branch, RepoOptions.base_branch(opts))

    branch = Repo.base_branch(%{}, repo_opts)

    {branch <> "\n", "", 0}
  end

  def run("working-branch", [identifier], opts, _cli_opts, command_opts) do
    command_opts
    |> maybe_put(:work_prefix, RepoOptions.work_prefix(opts))
    |> then(&Repo.working_branch(identifier, &1))
    |> Renderer.scalar()
  end

  def run("status", _args, opts, _cli_opts, command_opts) do
    opts
    |> RepoOptions.path()
    |> Repo.status(command_opts)
    |> Renderer.status()
  end

  def run("preflight", _args, opts, _cli_opts, command_opts) do
    repo_command_opts =
      command_opts
      |> maybe_put(:remote_url, RepoOptions.remote_url(opts))
      |> maybe_put(:base_branch, RepoOptions.base_branch(opts))

    Repo.preflight(RepoOptions.path(opts), RepoOptions.remote(opts), repo_command_opts)
    |> Renderer.preflight()
  end

  def run("diff", args, opts, cli_opts, command_opts) do
    diff_args =
      []
      |> maybe_append_flag("--merge", Keyword.get(cli_opts, :merge, false))
      |> maybe_append_flag("--cached", Keyword.get(cli_opts, :cached, false) or Keyword.get(cli_opts, :staged, false))
      |> Kernel.++(args)

    Repo.diff(RepoOptions.path(opts), diff_args, command_opts)
    |> Renderer.scalar()
  end

  def run("diff-check", args, opts, _cli_opts, command_opts) do
    Repo.diff_check(RepoOptions.path(opts), args, command_opts)
    |> Renderer.scalar()
  end

  def run("clone", [remote_url, target_path], _opts, cli_opts, command_opts) do
    repo_command_opts =
      command_opts
      |> maybe_put(:depth, Keyword.get(cli_opts, :depth))
      |> maybe_put(:branch, present_string(Keyword.get(cli_opts, :branch)))

    Repo.clone(remote_url, target_path, repo_command_opts)
    |> Renderer.scalar()
  end

  def run("fetch", _args, opts, _cli_opts, command_opts) do
    Repo.fetch(RepoOptions.path(opts), RepoOptions.remote(opts), command_opts)
    |> Renderer.scalar()
  end

  def run("merge", [ref], opts, cli_opts, command_opts) do
    repo_command_opts = maybe_put(command_opts, :ff_only, Keyword.get(cli_opts, :ff_only))

    Repo.merge(RepoOptions.path(opts), ref, repo_command_opts)
    |> Renderer.scalar()
  end

  def run("sync-base", _args, opts, cli_opts, command_opts) do
    repo_command_opts = maybe_put(command_opts, :ff_only, Keyword.get(cli_opts, :ff_only))
    base = RepoOptions.base_ref(cli_opts, opts, repo_command_opts)

    Repo.sync_base(RepoOptions.path(opts), RepoOptions.remote(opts), base, repo_command_opts)
    |> Renderer.scalar()
  end

  def run("enable-rerere", _args, opts, _cli_opts, command_opts) do
    Repo.enable_rerere(RepoOptions.path(opts), command_opts)
    |> Renderer.scalar()
  end

  def run("push", [branch], opts, cli_opts, command_opts) do
    repo_command_opts =
      command_opts
      |> maybe_put(:set_upstream, Keyword.get(cli_opts, :set_upstream))
      |> maybe_put(:force_with_lease, Keyword.get(cli_opts, :force_with_lease))

    Repo.push(RepoOptions.path(opts), RepoOptions.remote(opts), branch, repo_command_opts)
    |> Renderer.scalar()
  end

  def run("delete-remote-branch", [branch], opts, _cli_opts, command_opts) do
    Repo.delete_remote_branch(RepoOptions.path(opts), RepoOptions.remote(opts), branch, command_opts)
    |> Renderer.scalar()
  end

  def run("create-branch", [branch], opts, cli_opts, command_opts) do
    base_ref = cli_opts |> Keyword.get(:base, "HEAD") |> present_or_default("HEAD")

    Repo.create_branch(RepoOptions.path(opts), branch, base_ref, command_opts)
    |> Renderer.scalar()
  end

  def run("create-working-branch", [identifier], opts, cli_opts, command_opts) do
    repo_command_opts = maybe_put(command_opts, :work_prefix, RepoOptions.work_prefix(opts))
    base_ref = RepoOptions.working_branch_base_ref(cli_opts, opts, command_opts)

    Repo.create_working_branch(RepoOptions.path(opts), identifier, base_ref, repo_command_opts)
    |> Renderer.scalar()
  end

  def run("switch-branch", [branch], opts, _cli_opts, command_opts) do
    Repo.switch_branch(RepoOptions.path(opts), branch, command_opts)
    |> Renderer.scalar()
  end

  def run("stage-all", _args, opts, _cli_opts, command_opts) do
    Repo.stage_all(RepoOptions.path(opts), command_opts)
    |> Renderer.scalar()
  end

  def run("commit-all", args, opts, cli_opts, command_opts) do
    message = present_string(Keyword.get(cli_opts, :message)) || commit_message_arg(args)

    Repo.commit_all(RepoOptions.path(opts), message || "", command_opts)
    |> Renderer.scalar()
  end

  def run("commit-staged", args, opts, cli_opts, command_opts) do
    message = present_string(Keyword.get(cli_opts, :message)) || commit_message_arg(args)

    Repo.commit_staged(RepoOptions.path(opts), message || "", command_opts)
    |> Renderer.scalar()
  end

  defp commit_message_arg([]), do: nil
  defp commit_message_arg(args), do: args |> Enum.join(" ") |> present_string()

  defp present_or_default(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> default
      present -> present
    end
  end

  defp present_or_default(_value, default), do: default

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      present -> present
    end
  end

  defp present_string(_value), do: nil

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, false), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_append_flag(args, flag, true), do: args ++ [flag]
  defp maybe_append_flag(args, _flag, _value), do: args
end
