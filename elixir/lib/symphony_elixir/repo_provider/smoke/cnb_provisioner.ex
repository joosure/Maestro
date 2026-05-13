defmodule SymphonyElixir.RepoProvider.Smoke.CNBProvisioner do
  @moduledoc """
  CNB auto-provisioning workflow for repo-provider smoke tests.

  Manages the lifecycle of a temporary CNB pipeline branch: context
  creation, git clone, branch preparation, push, PR verification, CI
  run polling, and cleanup.

  This module is internal to the `Smoke` subsystem and should not be
  called directly by application code.
  """

  import SymphonyElixir.RepoProvider.Smoke.ProbeRunner,
    only: [probe: 2, run_probe: 3, synthetic_failure_probe: 2]

  alias SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.{Args, Context, Git, PRFlow, Runtime}

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Returns whether auto-provision needs to resolve the base branch.
  """
  @spec needs_base_resolution?(keyword(), map()) :: boolean()
  defdelegate needs_base_resolution?(opts, repo_config), to: Context

  @doc """
  Runs the full CNB auto-provision smoke flow.
  """
  @spec run(keyword(), String.t() | nil, map(), map(), map(), map()) :: [map()]
  def run(opts, provider_override, repo_config, env_map, cli_deps, deps) do
    preflight_results =
      [
        probe("current-kind", Args.provider_argv(provider_override, ["current-kind"])),
        probe("auth-status", Args.provider_argv(provider_override, ["auth-status"]))
      ]
      |> Enum.map(&run_probe(&1, cli_deps, deps))

    if Enum.any?(preflight_results, &(not &1.ok)) do
      preflight_results
    else
      case Context.build(opts, repo_config, env_map, deps) do
        {:ok, context} ->
          try do
            auto_provision_results(provider_override, cli_deps, deps, preflight_results, context)
          after
            Runtime.rm_rf(deps, context.temp_dir)
          end

        {:error, message} ->
          preflight_results ++ [synthetic_failure_probe("cnb-auto-provision", message)]
      end
    end
  end

  @doc false
  @spec provider_argv(nil | String.t(), [String.t()]) :: [String.t()]
  defdelegate provider_argv(provider_override, argv), to: Args

  @doc false
  @spec destructive_create_argv(String.t(), String.t(), String.t() | nil, String.t() | nil) :: [String.t()]
  defdelegate destructive_create_argv(title, body, base, head), to: Args

  @doc false
  @spec destructive_edited_body(String.t()) :: String.t()
  defdelegate destructive_edited_body(create_body), to: Args

  @doc false
  @spec created_pull(map()) :: {:ok, String.t(), String.t()} | {:error, String.t()}
  defdelegate created_pull(result), to: Args

  # ── Orchestration Pipeline ─────────────────────────────────────────

  defp auto_provision_results(provider_override, cli_deps, deps, acc, context) do
    {acc, context} = Git.maybe_resolve_base(acc, context, deps)

    case context.base do
      nil ->
        acc

      _base ->
        context
        |> Context.finalize()
        |> continue_after_base_resolution(provider_override, cli_deps, deps, acc)
    end
  end

  defp continue_after_base_resolution(context, provider_override, cli_deps, deps, acc) do
    clone_result = Git.clone_repo(context, deps)
    acc = acc ++ [clone_result]

    if clone_result.ok do
      continue_after_clone(context, provider_override, cli_deps, deps, acc)
    else
      acc
    end
  end

  defp continue_after_clone(context, provider_override, cli_deps, deps, acc) do
    prepare_result = Git.prepare_branch(context, deps)
    acc = acc ++ [prepare_result]

    if prepare_result.ok do
      continue_after_prepare(context, provider_override, cli_deps, deps, acc)
    else
      acc
    end
  end

  defp continue_after_prepare(context, provider_override, cli_deps, deps, acc) do
    push_result = Git.push_branch(context, deps)
    acc = acc ++ [push_result]

    if push_result.ok do
      context
      |> Map.put(:remote_branch?, true)
      |> PRFlow.run_pr_flow(provider_override, cli_deps, deps, acc)
    else
      acc
    end
  end
end
