defmodule SymphonyElixir.Repo.Context do
  @moduledoc """
  Runtime context for provider-neutral target repository settings.

  This module centralizes the repo-core settings that provider adapters may
  need when they read local Git facts: target path, remote name, configured
  remote URL, base branch, and generated branch prefix. Code-host provider
  settings remain owned by `SymphonyElixir.RepoProvider`.
  """

  alias SymphonyElixir.Repo

  @default_path "."
  @default_remote "origin"

  @type t :: %__MODULE__{
          path: Path.t(),
          remote: String.t(),
          remote_url: String.t() | nil,
          base_branch: String.t() | nil,
          work_prefix: String.t() | nil
        }

  defstruct path: @default_path,
            remote: @default_remote,
            remote_url: nil,
            base_branch: nil,
            work_prefix: nil

  @spec new(map() | struct() | nil, keyword()) :: t()
  def new(repo_config \\ nil, opts \\ []) when is_list(opts) do
    remote_config = map_field(repo_config, :remote)
    branch_config = map_field(repo_config, :branch)

    %__MODULE__{
      path: first_present([Keyword.get(opts, :path), map_field(repo_config, :path), @default_path]),
      remote: first_present([Keyword.get(opts, :remote), map_field(remote_config, :name), @default_remote]),
      remote_url: first_present([Keyword.get(opts, :remote_url), map_field(remote_config, :url)]),
      base_branch: first_present([Keyword.get(opts, :base_branch), map_field(repo_config, :base_branch)]),
      work_prefix: first_present([Keyword.get(opts, :work_prefix), map_field(branch_config, :work_prefix)])
    }
  end

  @spec path(map() | struct() | nil, keyword()) :: Path.t()
  def path(repo_config \\ nil, opts \\ []), do: new(repo_config, opts).path

  @spec remote_name(map() | struct() | nil, keyword()) :: String.t()
  def remote_name(repo_config \\ nil, opts \\ []), do: new(repo_config, opts).remote

  @spec configured_remote_url(map() | struct() | nil, keyword()) :: String.t() | nil
  def configured_remote_url(repo_config \\ nil, opts \\ []), do: new(repo_config, opts).remote_url

  @spec work_prefix(map() | struct() | nil, keyword()) :: String.t() | nil
  def work_prefix(repo_config \\ nil, opts \\ []), do: new(repo_config, opts).work_prefix

  @spec repo_opts(map() | struct() | nil, keyword()) :: keyword()
  def repo_opts(repo_config \\ nil, opts \\ []) when is_list(opts) do
    context = new(repo_config, opts)

    opts
    |> Keyword.put(:path, context.path)
    |> Keyword.put(:remote, context.remote)
    |> maybe_put(:remote_url, context.remote_url)
    |> maybe_put(:base_branch, context.base_branch)
    |> maybe_put(:work_prefix, context.work_prefix)
  end

  @spec base_branch(map() | struct() | nil, keyword()) :: String.t()
  def base_branch(repo_config \\ nil, opts \\ []) when is_list(opts) do
    context = new(repo_config, opts)
    base_repo_config = if context.base_branch, do: %{base_branch: context.base_branch}, else: nil

    Repo.base_branch(base_repo_config, repo_opts(repo_config, opts))
  end

  @spec working_branch(String.t(), keyword()) :: Repo.result(String.t())
  def working_branch(identifier, opts \\ [])

  def working_branch(identifier, opts) when is_binary(identifier) and is_list(opts) do
    working_branch(nil, identifier, opts)
  end

  @spec working_branch(map() | struct() | nil, String.t()) :: Repo.result(String.t())
  def working_branch(repo_config, identifier) when is_binary(identifier) do
    working_branch(repo_config, identifier, [])
  end

  @spec working_branch(map() | struct() | nil, String.t(), keyword()) :: Repo.result(String.t())
  def working_branch(repo_config, identifier, opts) when is_binary(identifier) and is_list(opts) do
    repo_config
    |> repo_opts(opts)
    |> then(&Repo.working_branch(identifier, &1))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp first_present(values) when is_list(values) do
    Enum.find_value(values, &present_string/1)
  end

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_string(_value), do: nil

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
end
