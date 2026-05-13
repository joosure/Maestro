defmodule SymphonyElixir.Repo.Git do
  @moduledoc """
  Git-backed implementation of the provider-neutral repo-core API.

  All functions scope Git commands to the supplied repository path when one is
  provided. Tests may inject `:command_runner` with the same two-argument shape
  used by repo-provider command tests: `(command, args -> result)`.
  """

  alias SymphonyElixir.Repo.Error
  alias SymphonyElixir.Repo.Git.{Branches, Command, Commits, Inspection, Remote}
  alias SymphonyElixir.Repo.Status

  @type command_result :: {:ok, String.t()} | {:error, {non_neg_integer() | atom(), String.t()}}
  @type result(t) :: {:ok, t} | {:error, Error.t()}

  @spec root(Path.t(), keyword()) :: result(Path.t())
  def root(path \\ ".", opts \\ []) when is_binary(path) and is_list(opts), do: Inspection.root(path, opts)

  @spec current_branch(Path.t(), keyword()) :: result(String.t())
  def current_branch(path \\ ".", opts \\ []) when is_binary(path) and is_list(opts),
    do: Inspection.current_branch(path, opts)

  @spec head_sha(Path.t(), keyword()) :: result(String.t())
  def head_sha(path \\ ".", opts \\ []) when is_binary(path) and is_list(opts),
    do: Inspection.head_sha(path, opts)

  @spec published_head_sha(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def published_head_sha(path, remote, branch, opts \\ [])
      when is_binary(path) and is_binary(remote) and is_binary(branch) and is_list(opts),
      do: Remote.published_head_sha(path, remote, branch, opts)

  @spec remote_url(Path.t(), String.t(), keyword()) :: result(String.t())
  def remote_url(path \\ ".", remote \\ "origin", opts \\ [])
      when is_binary(path) and is_binary(remote) and is_list(opts),
      do: Remote.remote_url(path, remote, opts)

  @spec remote_default_branch(Path.t(), String.t(), keyword()) :: result(String.t())
  def remote_default_branch(path \\ ".", remote \\ "origin", opts \\ [])
      when is_binary(path) and is_binary(remote) and is_list(opts),
      do: Remote.remote_default_branch(path, remote, opts)

  @spec remote_default_branch_from_url(String.t(), keyword()) :: result(String.t())
  def remote_default_branch_from_url(remote_url, opts \\ []) when is_binary(remote_url) and is_list(opts),
    do: Remote.remote_default_branch_from_url(remote_url, opts)

  @spec status(Path.t(), keyword()) :: result(Status.t())
  def status(path \\ ".", opts \\ []) when is_binary(path) and is_list(opts), do: Inspection.status(path, opts)

  @spec diff(Path.t(), [String.t()], keyword()) :: result(String.t())
  def diff(path \\ ".", args \\ [], opts \\ [])
      when is_binary(path) and is_list(args) and is_list(opts),
      do: Inspection.diff(path, args, opts)

  @spec diff_check(Path.t(), keyword()) :: result(String.t())
  def diff_check(path \\ ".", opts \\ []) when is_binary(path) and is_list(opts),
    do: Inspection.diff_check(path, opts)

  @spec diff_check(Path.t(), [String.t()], keyword()) :: result(String.t())
  def diff_check(path, args, opts) when is_binary(path) and is_list(args) and is_list(opts),
    do: Inspection.diff_check(path, args, opts)

  @spec fetch(Path.t(), String.t(), keyword()) :: result(String.t())
  def fetch(path \\ ".", remote \\ "origin", opts \\ [])
      when is_binary(path) and is_binary(remote) and is_list(opts),
      do: Remote.fetch(path, remote, opts)

  @spec merge(Path.t(), String.t(), keyword()) :: result(String.t())
  def merge(path, ref, opts \\ [])
      when is_binary(path) and is_binary(ref) and is_list(opts),
      do: Branches.merge(path, ref, opts)

  @spec sync_base(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def sync_base(path \\ ".", remote \\ "origin", base_branch \\ "main", opts \\ [])
      when is_binary(path) and is_binary(remote) and is_binary(base_branch) and is_list(opts),
      do: Branches.sync_base(path, remote, base_branch, opts)

  @spec enable_rerere(Path.t(), keyword()) :: result(String.t())
  def enable_rerere(path \\ ".", opts \\ []) when is_binary(path) and is_list(opts),
    do: Commits.enable_rerere(path, opts)

  @spec stage_all(Path.t(), keyword()) :: result(String.t())
  def stage_all(path \\ ".", opts \\ []) when is_binary(path) and is_list(opts), do: Commits.stage_all(path, opts)

  @spec clone(String.t(), Path.t(), keyword()) :: result(String.t())
  def clone(remote_url, target_path, opts \\ []) when is_binary(remote_url) and is_binary(target_path) and is_list(opts),
    do: Remote.clone(remote_url, target_path, opts)

  @spec clone(String.t(), Path.t(), String.t(), keyword()) :: result(String.t())
  def clone(remote_url, target_path, branch, opts)
      when is_binary(remote_url) and is_binary(target_path) and is_binary(branch) and is_list(opts),
      do: Remote.clone(remote_url, target_path, branch, opts)

  @spec push(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def push(path, remote, branch, opts \\ [])
      when is_binary(path) and is_binary(remote) and is_binary(branch) and is_list(opts),
      do: Remote.push(path, remote, branch, opts)

  @spec delete_remote_branch(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def delete_remote_branch(path, remote, branch, opts \\ [])
      when is_binary(path) and is_binary(remote) and is_binary(branch) and is_list(opts),
      do: Remote.delete_remote_branch(path, remote, branch, opts)

  @spec create_branch(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def create_branch(path, branch, base_ref \\ "HEAD", opts \\ [])
      when is_binary(path) and is_binary(branch) and is_binary(base_ref) and is_list(opts),
      do: Branches.create_branch(path, branch, base_ref, opts)

  @spec switch_branch(Path.t(), String.t(), keyword()) :: result(String.t())
  def switch_branch(path, branch, opts \\ [])
      when is_binary(path) and is_binary(branch) and is_list(opts),
      do: Branches.switch_branch(path, branch, opts)

  @spec commit_all(Path.t(), String.t(), keyword()) :: result(String.t() | :noop)
  def commit_all(path, message, opts \\ [])
      when is_binary(path) and is_binary(message) and is_list(opts),
      do: Commits.commit_all(path, message, opts)

  @spec commit_staged(Path.t(), String.t(), keyword()) :: result(String.t())
  def commit_staged(path, message, opts \\ [])
      when is_binary(path) and is_binary(message) and is_list(opts),
      do: Commits.commit_staged(path, message, opts)

  @spec default_command_runner(String.t(), [String.t()]) :: command_result()
  def default_command_runner(command, args), do: Command.default_runner(command, args)
end
