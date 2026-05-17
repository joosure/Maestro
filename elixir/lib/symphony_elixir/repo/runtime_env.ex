defmodule SymphonyElixir.Repo.RuntimeEnv do
  @moduledoc false

  @base_branch_env "SYMPHONY_REPO_BASE_BRANCH"
  @branch_work_prefix_env "SYMPHONY_REPO_BRANCH_WORK_PREFIX"
  @default_base_branch "main"
  @default_work_prefix "symphony"

  @spec base_branch_env() :: String.t()
  def base_branch_env, do: @base_branch_env

  @spec branch_work_prefix_env() :: String.t()
  def branch_work_prefix_env, do: @branch_work_prefix_env

  @spec default_base_branch() :: String.t()
  def default_base_branch, do: @default_base_branch

  @spec default_work_prefix() :: String.t()
  def default_work_prefix, do: @default_work_prefix

  @spec base_branch(map() | [{String.t(), String.t()}] | nil) :: String.t() | nil
  def base_branch(env \\ System.get_env())
  def base_branch(env) when is_list(env), do: env |> Map.new() |> base_branch()
  def base_branch(env) when is_map(env), do: env |> Map.get(@base_branch_env) |> blank_to_nil()
  def base_branch(nil), do: nil

  @spec branch_work_prefix(map() | [{String.t(), String.t()}] | nil) :: String.t() | nil
  def branch_work_prefix(env \\ System.get_env())
  def branch_work_prefix(env) when is_list(env), do: env |> Map.new() |> branch_work_prefix()
  def branch_work_prefix(env) when is_map(env), do: env |> Map.get(@branch_work_prefix_env) |> blank_to_nil()
  def branch_work_prefix(nil), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
