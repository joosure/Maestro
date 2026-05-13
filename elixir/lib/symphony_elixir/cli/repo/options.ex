defmodule SymphonyElixir.CLI.Repo.Options do
  @moduledoc false

  alias SymphonyElixir.Config
  alias SymphonyElixir.Repo

  @type repo_opts :: %{
          path: String.t(),
          remote: String.t(),
          remote_url: String.t() | nil,
          base_branch: String.t() | nil,
          work_prefix: String.t() | nil
        }

  @spec command_opts(map()) :: keyword()
  def command_opts(deps) do
    case Map.get(deps, :command_opts) do
      nil -> []
      fun when is_function(fun, 0) -> fun.()
    end
  end

  @spec repo_config(map()) :: map() | struct() | nil
  def repo_config(deps) do
    case Map.get(deps, :repo_config) do
      nil -> runtime_repo_config()
      fun when is_function(fun, 0) -> fun.()
    end
  end

  @spec repo_opts(keyword(), map() | struct() | nil) :: repo_opts()
  def repo_opts(opts, repo_config) do
    %{
      path: resolve_path(opts, repo_config),
      remote: resolve_remote(opts, repo_config),
      remote_url: resolve_remote_url(opts, repo_config),
      base_branch: resolve_base_branch(repo_config),
      work_prefix: resolve_work_prefix(opts, repo_config)
    }
  end

  @spec path(repo_opts()) :: String.t()
  def path(%{path: path}), do: path

  @spec remote(repo_opts()) :: String.t()
  def remote(%{remote: remote}), do: remote

  @spec remote_url(repo_opts()) :: String.t() | nil
  def remote_url(%{remote_url: remote_url}), do: present_string(remote_url)

  @spec base_branch(repo_opts()) :: String.t() | nil
  def base_branch(%{base_branch: base_branch}), do: present_string(base_branch)

  @spec work_prefix(repo_opts()) :: String.t() | nil
  def work_prefix(%{work_prefix: work_prefix}), do: present_string(work_prefix)

  @spec base_ref(keyword(), repo_opts(), keyword()) :: String.t()
  def base_ref(cli_opts, opts, command_opts) do
    present_string(Keyword.get(cli_opts, :base)) ||
      base_branch_name(opts, command_opts)
  end

  @spec working_branch_base_ref(keyword(), repo_opts(), keyword()) :: String.t()
  def working_branch_base_ref(cli_opts, opts, command_opts) do
    present_string(Keyword.get(cli_opts, :base)) ||
      "#{remote(opts)}/#{base_branch_name(opts, command_opts)}"
  end

  defp runtime_repo_config do
    case Config.settings() do
      {:ok, settings} -> settings.repo
      {:error, _reason} -> nil
    end
  end

  defp resolve_path(opts, repo_config) do
    opts
    |> Keyword.get(:path, map_field(repo_config, :path) || ".")
    |> present_or_default(".")
  end

  defp resolve_remote(opts, repo_config) do
    configured_remote = map_field(map_field(repo_config, :remote), :name)

    opts
    |> Keyword.get(:remote, configured_remote || "origin")
    |> present_or_default("origin")
  end

  defp resolve_remote_url(opts, repo_config) do
    remote_config = map_field(repo_config, :remote)

    opts
    |> Keyword.get(:remote_url, map_field(remote_config, :url))
    |> present_string()
  end

  defp resolve_base_branch(repo_config), do: repo_config |> map_field(:base_branch) |> present_string()

  defp resolve_work_prefix(opts, repo_config) do
    branch_config = map_field(repo_config, :branch)

    opts
    |> Keyword.get(:work_prefix, map_field(branch_config, :work_prefix))
    |> present_string()
  end

  defp base_branch_name(opts, command_opts) do
    base_branch(opts) ||
      Repo.base_branch(%{}, Keyword.merge(command_opts, path: path(opts), remote: remote(opts)))
  end

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
end
