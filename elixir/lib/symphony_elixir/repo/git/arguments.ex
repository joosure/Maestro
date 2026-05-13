defmodule SymphonyElixir.Repo.Git.Arguments do
  @moduledoc false

  @spec append_depth([String.t()], pos_integer() | String.t() | term()) :: [String.t()]
  def append_depth(args, depth) when is_integer(depth) and depth > 0, do: args ++ ["--depth", Integer.to_string(depth)]
  def append_depth(args, depth) when is_binary(depth) and depth != "", do: args ++ ["--depth", depth]
  def append_depth(args, _depth), do: args

  @spec append_branch([String.t()], String.t() | term()) :: [String.t()]
  def append_branch(args, branch) when is_binary(branch) and branch != "", do: args ++ ["--branch", branch]
  def append_branch(args, _branch), do: args

  @spec append_force_with_lease([String.t()], boolean()) :: [String.t()]
  def append_force_with_lease(args, true), do: args ++ ["--force-with-lease"]
  def append_force_with_lease(args, _force_with_lease), do: args

  @spec append_set_upstream([String.t()], boolean()) :: [String.t()]
  def append_set_upstream(args, true), do: args ++ ["-u"]
  def append_set_upstream(args, _set_upstream), do: args
end
