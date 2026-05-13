defmodule SymphonyElixir.Repo do
  @moduledoc """
  Provider-neutral facade for target repository operations.

  This module owns local Git/repo facts such as repository root, current branch,
  head SHA, remote URL, base branch, and working-tree status. Code-host
  operations remain in `SymphonyElixir.RepoProvider`.
  """

  alias SymphonyElixir.Repo.Branch
  alias SymphonyElixir.Repo.Error
  alias SymphonyElixir.Repo.Git
  alias SymphonyElixir.Repo.Preflight
  alias SymphonyElixir.Repo.Status

  @type result(t) :: {:ok, t} | {:error, Error.t()}

  @spec root(Path.t(), keyword()) :: result(Path.t())
  def root(path \\ ".", opts \\ []), do: Git.root(path, opts)

  @spec current_branch(Path.t(), keyword()) :: result(String.t())
  def current_branch(path \\ ".", opts \\ []), do: Git.current_branch(path, opts)

  @spec head_sha(Path.t(), keyword()) :: result(String.t())
  def head_sha(path \\ ".", opts \\ []), do: Git.head_sha(path, opts)

  @spec published_head_sha(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def published_head_sha(path, remote, branch, opts \\ []),
    do: Git.published_head_sha(path, remote, branch, opts)

  @spec remote_url(Path.t(), String.t(), keyword()) :: result(String.t())
  def remote_url(path \\ ".", remote \\ "origin", opts \\ []), do: Git.remote_url(path, remote, opts)

  @spec status(Path.t(), keyword()) :: result(Status.t())
  def status(path \\ ".", opts \\ []), do: Git.status(path, opts)

  @spec diff(Path.t(), [String.t()], keyword()) :: result(String.t())
  def diff(path \\ ".", args \\ [], opts \\ []), do: Git.diff(path, args, opts)

  @spec diff_check(Path.t(), keyword()) :: result(String.t())
  def diff_check(path \\ ".", opts \\ []), do: Git.diff_check(path, opts)

  @spec diff_check(Path.t(), [String.t()], keyword()) :: result(String.t())
  def diff_check(path, args, opts), do: Git.diff_check(path, args, opts)

  @spec preflight(Path.t(), String.t(), keyword()) :: result(Preflight.t())
  def preflight(path \\ ".", remote \\ "origin", opts \\ []) do
    with {:ok, root} <- root(path, opts),
         {:ok, current_branch} <- current_branch(root, opts),
         {:ok, head_sha} <- head_sha(root, opts),
         {:ok, remote_url} <- preflight_remote_url(root, remote, opts) do
      {:ok,
       %Preflight{
         path: path,
         root: root,
         remote: remote,
         remote_url: remote_url,
         base_branch: base_branch(%{}, Keyword.merge(opts, path: root, remote: remote)),
         current_branch: current_branch,
         head_sha: head_sha
       }}
    end
  end

  @spec remote_default_branch(Path.t(), String.t(), keyword()) :: result(String.t())
  def remote_default_branch(path \\ ".", remote \\ "origin", opts \\ []),
    do: Git.remote_default_branch(path, remote, opts)

  @spec remote_default_branch_from_url(String.t(), keyword()) :: result(String.t())
  def remote_default_branch_from_url(remote_url, opts \\ []), do: Git.remote_default_branch_from_url(remote_url, opts)

  @spec base_branch(map() | struct() | nil, keyword()) :: String.t()
  def base_branch(repo_config \\ nil, opts \\ []) when is_list(opts) do
    configured =
      map_field(repo_config, :base_branch) ||
        Keyword.get(opts, :base_branch) ||
        System.get_env("SYMPHONY_REPO_BASE_BRANCH")

    case present_string(configured) do
      branch when is_binary(branch) -> branch
      nil -> optional_remote_default_branch(opts) || "main"
    end
  end

  @spec working_branch(String.t(), keyword()) :: result(String.t())
  def working_branch(identifier, opts \\ []), do: Branch.working_branch(identifier, opts)

  @spec clean?(Path.t(), keyword()) :: result(boolean())
  def clean?(path \\ ".", opts \\ []) do
    case status(path, opts) do
      {:ok, %Status{clean?: clean?}} -> {:ok, clean?}
      {:error, error} -> {:error, error}
    end
  end

  @spec fetch(Path.t(), String.t(), keyword()) :: result(String.t())
  def fetch(path \\ ".", remote \\ "origin", opts \\ []), do: Git.fetch(path, remote, opts)

  @spec merge(Path.t(), String.t(), keyword()) :: result(String.t())
  def merge(path, ref, opts \\ []), do: Git.merge(path, ref, opts)

  @spec sync_base(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def sync_base(path \\ ".", remote \\ "origin", base_branch \\ "main", opts \\ []),
    do: Git.sync_base(path, remote, base_branch, opts)

  @spec enable_rerere(Path.t(), keyword()) :: result(String.t())
  def enable_rerere(path \\ ".", opts \\ []), do: Git.enable_rerere(path, opts)

  @spec stage_all(Path.t(), keyword()) :: result(String.t())
  def stage_all(path \\ ".", opts \\ []), do: Git.stage_all(path, opts)

  @spec clone(String.t(), Path.t(), keyword()) :: result(String.t())
  def clone(remote_url, target_path, opts \\ []) when is_list(opts), do: Git.clone(remote_url, target_path, opts)

  @spec clone(String.t(), Path.t(), String.t(), keyword()) :: result(String.t())
  def clone(remote_url, target_path, branch, opts), do: Git.clone(remote_url, target_path, branch, opts)

  @spec push(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def push(path, remote, branch, opts \\ []), do: Git.push(path, remote, branch, opts)

  @spec delete_remote_branch(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def delete_remote_branch(path, remote, branch, opts \\ []), do: Git.delete_remote_branch(path, remote, branch, opts)

  @spec create_branch(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def create_branch(path, branch, base_ref \\ "HEAD", opts \\ []),
    do: Git.create_branch(path, branch, base_ref, opts)

  @spec create_working_branch(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def create_working_branch(path, identifier, base_ref \\ "HEAD", opts \\ []) do
    with {:ok, branch} <- working_branch(identifier, opts) do
      Git.create_branch(path, branch, base_ref, opts)
    end
  end

  @spec switch_branch(Path.t(), String.t(), keyword()) :: result(String.t())
  def switch_branch(path, branch, opts \\ []), do: Git.switch_branch(path, branch, opts)

  @spec commit_all(Path.t(), String.t(), keyword()) :: result(String.t() | :noop)
  def commit_all(path, message, opts \\ []), do: Git.commit_all(path, message, opts)

  @spec commit_staged(Path.t(), String.t(), keyword()) :: result(String.t())
  def commit_staged(path, message, opts \\ []), do: Git.commit_staged(path, message, opts)

  defp map_field(nil, _field), do: nil

  defp map_field(%_{} = struct, field) when is_atom(field) do
    struct
    |> Map.from_struct()
    |> map_field(field)
  end

  defp map_field(map, field) when is_map(map) and is_atom(field) do
    Map.get(map, field) || Map.get(map, Atom.to_string(field))
  end

  defp map_field(_value, _field), do: nil

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_string(_value), do: nil

  defp optional_remote_default_branch(opts) do
    path = Keyword.get(opts, :path, ".")
    remote = Keyword.get(opts, :remote, "origin")

    case remote_default_branch(path, remote, opts) do
      {:ok, branch} -> branch
      {:error, _error} -> nil
    end
  end

  defp preflight_remote_url(root, remote, opts) do
    case opts |> Keyword.get(:remote_url) |> present_string() do
      url when is_binary(url) -> {:ok, url}
      nil -> remote_url(root, remote, opts)
    end
  end
end
