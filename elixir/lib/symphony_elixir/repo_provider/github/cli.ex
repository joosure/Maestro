defmodule SymphonyElixir.RepoProvider.GitHub.CLI do
  @moduledoc """
  Shared CLI infrastructure for the GitHub adapter.

  Encapsulates `gh` CLI invocation, JSON output decoding, and
  repository resolution. All handler modules (`PullRequestHandler`,
  `RunHandler`, `ApiHandler`) delegate to this module for shell
  interaction, keeping provider-specific logic centralized.

  ## Design

  The module mirrors the role of `CNB.HttpClient` — a thin
  infrastructure layer that the domain handlers build upon.
  """

  alias SymphonyElixir.Repo, as: TargetRepo
  alias SymphonyElixir.Repo.Context, as: RepoContext
  alias SymphonyElixir.RepoProvider.Config, as: RepoConfig
  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Shell

  @type repo_config :: map()
  @type command_result :: {:ok, String.t()} | {:error, {non_neg_integer() | atom(), String.t()}}

  # ── Command Execution ──────────────────────────────────────────

  @spec run_command(String.t(), [String.t()], keyword()) :: command_result()
  def run_command(command, args, opts), do: Shell.run_command(command, args, opts)

  @spec find_executable(String.t(), keyword()) :: String.t() | nil
  def find_executable(command, opts), do: Shell.find_executable(command, opts)

  @spec run_json_command(String.t(), [String.t()], keyword(), [non_neg_integer()]) ::
          {:ok, term()} | {:error, Error.t()}
  def run_json_command(command, args, opts, allowed_error_statuses \\ []) do
    case run_command(command, args, opts) do
      {:ok, output} ->
        decode_json_output(output, :github_invalid_payload, "Failed to decode GitHub JSON output")

      {:error, {:enoent, _output}} ->
        {:error, Error.missing_tooling("gh", "GitHub")}

      {:error, {status, output}} ->
        if status in allowed_error_statuses do
          decode_json_output(output, :github_invalid_payload, "Failed to decode GitHub JSON output")
        else
          {:error, Error.runtime_failure(:github_cli_status, String.trim(output))}
        end
    end
  end

  # ── JSON Helpers ────────────────────────────────────────────────

  @spec decode_json_output(String.t(), atom(), String.t()) ::
          {:ok, term()} | {:error, Error.t()}
  def decode_json_output(output, code, message) do
    case Jason.decode(output) do
      {:ok, payload} -> {:ok, payload}
      {:error, reason} -> {:error, Error.runtime_failure(code, message, reason)}
    end
  end

  @spec expect_list(term(), atom(), String.t()) :: {:ok, list()} | {:error, Error.t()}
  def expect_list(payload, _code, _message) when is_list(payload), do: {:ok, payload}
  def expect_list(payload, code, message), do: {:error, Error.runtime_failure(code, message, payload)}

  @spec expect_map(term(), atom(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def expect_map(payload, _code, _message) when is_map(payload), do: {:ok, payload}
  def expect_map(payload, code, message), do: {:error, Error.runtime_failure(code, message, payload)}

  # ── Repository Resolution ──────────────────────────────────────

  @spec resolve_repository(repo_config(), keyword()) :: String.t() | nil
  def resolve_repository(repo, opts \\ []) when is_map(repo) do
    present_string(opts[:repo]) ||
      present_string(configured_repository(repo)) ||
      origin_repository_slug(repo, opts)
  end

  @spec require_repository(repo_config(), keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def require_repository(repo, opts) do
    case resolve_repository(repo, opts) do
      repository when is_binary(repository) and repository != "" ->
        {:ok, repository}

      _other ->
        {:error,
         Error.runtime_failure(
           :missing_github_repository_slug,
           "GitHub provider requires a repository slug. Set repo.provider.repository or configure a GitHub remote."
         )}
    end
  end

  @spec configured_repository(repo_config()) :: String.t() | nil
  def configured_repository(repo), do: RepoConfig.repository(repo)

  @spec parse_repository_slug(String.t()) :: String.t() | nil
  def parse_repository_slug(remote_url) when is_binary(remote_url) do
    case Regex.run(~r{(?:github\.com[:/])([^/:]+/[^/]+?)(?:\.git)?$}, remote_url, capture: :all_but_first) do
      [repository] -> repository
      _ -> nil
    end
  end

  @spec resolve_pr_target(keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def resolve_pr_target(opts) when is_list(opts), do: resolve_pr_target(%{}, opts)

  @spec resolve_pr_target(repo_config(), keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def resolve_pr_target(repo, opts) when is_map(repo) and is_list(opts) do
    case present_string(Keyword.get(opts, :number)) do
      target when is_binary(target) ->
        {:ok, target}

      nil ->
        current_branch(repo, opts)
    end
  end

  @spec current_branch(keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def current_branch(opts) when is_list(opts), do: current_branch(%{}, opts)

  @spec current_branch(repo_config(), keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def current_branch(repo, opts) when is_map(repo) and is_list(opts) do
    case TargetRepo.current_branch(RepoContext.path(repo, opts), opts) do
      {:ok, branch} ->
        {:ok, branch}

      {:error, %TargetRepo.Error{code: :missing_tooling}} ->
        {:error,
         Error.runtime_failure(
           :github_current_branch_required,
           "GitHub PR commands without an explicit number require git in PATH to resolve the current branch"
         )}

      {:error, %TargetRepo.Error{code: :detached_head}} ->
        {:error,
         Error.runtime_failure(
           :github_current_branch_required,
           "GitHub PR commands without an explicit number require a current git branch"
         )}

      {:error, %TargetRepo.Error{} = error} ->
        {:error,
         Error.runtime_failure(
           :github_current_branch_required,
           "GitHub PR commands without an explicit number require resolving the current git branch",
           error
         )}
    end
  end

  # ── CLI Argument Helpers ───────────────────────────────────────

  @spec maybe_append_number([String.t()], String.t() | nil) :: [String.t()]
  def maybe_append_number(args, nil), do: args
  def maybe_append_number(args, number) when is_binary(number), do: args ++ [number]

  @spec maybe_append_option([String.t()], String.t(), String.t() | nil) :: [String.t()]
  def maybe_append_option(args, _flag, nil), do: args
  def maybe_append_option(args, _flag, ""), do: args
  def maybe_append_option(args, flag, value) when is_binary(value), do: args ++ [flag, value]

  @spec maybe_append_integer_option([String.t()], String.t(), integer() | nil) :: [String.t()]
  def maybe_append_integer_option(args, _flag, nil), do: args

  def maybe_append_integer_option(args, flag, value) when is_integer(value),
    do: args ++ [flag, Integer.to_string(value)]

  @spec enoent_error() :: Error.t()
  def enoent_error, do: Error.missing_tooling("gh", "GitHub")

  @spec extract_scalar_output(String.t()) :: String.t()
  def extract_scalar_output(output), do: String.trim(output)

  # ── Private ──────────────────────────────────────────────────────

  defp origin_repository_slug(repo, opts) do
    context = RepoContext.new(repo, opts)

    case TargetRepo.remote_url(context.path, context.remote, opts) do
      {:ok, output} ->
        parse_repository_slug(output)

      {:error, _reason} ->
        nil
    end
  end

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_string(_value), do: nil
end
