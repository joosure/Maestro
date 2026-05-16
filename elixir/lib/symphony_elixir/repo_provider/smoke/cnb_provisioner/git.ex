defmodule SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.Git do
  @moduledoc false

  import SymphonyElixir.RepoProvider.Smoke.ProbeRunner, only: [run_system_step: 3]

  alias SymphonyElixir.Repo, as: TargetRepo
  alias SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.{Runtime, Settings}

  @spec maybe_resolve_base([map()], map(), map()) :: {[map()], map()}
  def maybe_resolve_base(acc, %{base: base} = context, _deps) when is_binary(base), do: {acc, context}

  def maybe_resolve_base(acc, context, deps) do
    result =
      run_system_step("git-resolve-base", deps, fn ->
        case TargetRepo.remote_default_branch_from_url(
               context.clone_url,
               Runtime.repo_command_opts(deps, git_config: Runtime.cnb_git_auth_config(context))
             ) do
          {:ok, branch} ->
            %{ok: true, exit_code: 0, stdout: "", summary: branch}

          {:error, %TargetRepo.Error{} = error} ->
            %{
              ok: false,
              exit_code: error.exit_code,
              stderr: Runtime.repo_error_output(error),
              summary: Runtime.repo_error_summary(error)
            }
        end
      end)

    if result.ok do
      {acc ++ [result], %{context | base: result.summary}}
    else
      {acc ++ [result], context}
    end
  end

  @spec clone_repo(map(), map()) :: map()
  def clone_repo(context, deps) do
    run_system_step("git-clone", deps, fn ->
      case TargetRepo.clone(
             context.clone_url,
             context.worktree,
             context.base,
             Runtime.repo_command_opts(deps, depth: 1, git_config: Runtime.cnb_git_auth_config(context))
           ) do
        {:ok, output} ->
          %{
            ok: true,
            exit_code: 0,
            stdout: output,
            summary: "cloned #{context.repository} at #{context.base}"
          }

        {:error, %TargetRepo.Error{} = error} ->
          %{
            ok: false,
            exit_code: error.exit_code,
            stderr: Runtime.repo_error_output(error),
            summary: Runtime.repo_error_summary(error)
          }
      end
    end)
  end

  @spec prepare_branch(map(), map()) :: map()
  def prepare_branch(context, deps) do
    run_system_step("git-prepare-cnb-pipeline", deps, fn ->
      pipeline_path = Path.join(context.worktree, ".cnb.yml")

      with {:ok, _branch} <- TargetRepo.create_branch(context.worktree, context.head, "HEAD", Runtime.repo_command_opts(deps)),
           :ok <- Runtime.write_file(deps, pipeline_path, Settings.pipeline(context.head)),
           {:ok, _sha_or_noop} <-
             TargetRepo.commit_all(
               context.worktree,
               Settings.commit_message(),
               Runtime.repo_command_opts(deps, git_config: Runtime.git_identity_config())
             ) do
        %{
          ok: true,
          exit_code: 0,
          stdout: "",
          summary: "prepared #{context.head} with temporary .cnb.yml"
        }
      else
        {:error, %TargetRepo.Error{} = error} ->
          %{
            ok: false,
            exit_code: error.exit_code,
            stderr: Runtime.repo_error_output(error),
            summary: Runtime.repo_error_summary(error)
          }

        {:error, reason} ->
          %{
            ok: false,
            exit_code: 1,
            stderr: inspect(reason),
            summary: "Failed to write temporary .cnb.yml: #{inspect(reason)}"
          }
      end
    end)
  end

  @spec push_branch(map(), map()) :: map()
  def push_branch(context, deps) do
    run_system_step("git-push-cnb-pipeline", deps, fn ->
      case TargetRepo.push(
             context.worktree,
             "origin",
             context.head,
             Runtime.repo_command_opts(deps, set_upstream: true, git_config: Runtime.cnb_git_auth_config(context))
           ) do
        {:ok, output} ->
          %{
            ok: true,
            exit_code: 0,
            stdout: output,
            summary: "pushed #{context.head}"
          }

        {:error, %TargetRepo.Error{} = error} ->
          %{
            ok: false,
            exit_code: error.exit_code,
            stderr: Runtime.repo_error_output(error),
            summary: Runtime.repo_error_summary(error)
          }
      end
    end)
  end

  @spec delete_branch(map(), map()) :: map()
  def delete_branch(context, deps) do
    run_system_step("git-delete-cnb-pipeline-branch", deps, fn ->
      case TargetRepo.delete_remote_branch(
             context.worktree,
             "origin",
             context.head,
             Runtime.repo_command_opts(deps, git_config: Runtime.cnb_git_auth_config(context))
           ) do
        {:ok, output} ->
          %{ok: true, exit_code: 0, stdout: output, summary: "deleted remote branch #{context.head}"}

        {:error, %TargetRepo.Error{code: :branch_not_found} = error} ->
          %{ok: true, exit_code: 0, stdout: Runtime.repo_error_output(error), summary: "remote branch #{context.head} was already absent"}

        {:error, %TargetRepo.Error{} = error} ->
          %{
            ok: false,
            exit_code: error.exit_code,
            stderr: Runtime.repo_error_output(error),
            summary: Runtime.repo_error_summary(error)
          }
      end
    end)
  end
end
