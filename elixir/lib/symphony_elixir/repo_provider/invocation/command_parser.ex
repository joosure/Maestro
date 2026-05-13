defmodule SymphonyElixir.RepoProvider.Invocation.CommandParser do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Invocation
  alias SymphonyElixir.RepoProvider.Invocation.{Api, LandWatch, PullRequest, Reviews, Runs}

  @spec parse([String.t()]) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse(argv) when is_list(argv) do
    with {:ok, provider_override, rest} <- parse_provider(argv),
         {:ok, %Invocation{} = invocation} <- parse_command(rest) do
      {:ok, %{invocation | provider_override: provider_override}}
    end
  end

  defp parse_provider(["--provider", kind | rest]) when is_binary(kind) and kind != "" do
    {:ok, kind, rest}
  end

  defp parse_provider(["--provider"]) do
    {:error, Error.invalid_invocation("Option --provider requires a value")}
  end

  defp parse_provider(argv), do: {:ok, nil, argv}

  defp parse_command(["current-kind"]) do
    {:ok, %Invocation{command: :current_kind}}
  end

  defp parse_command(["auth-status"]) do
    {:ok, %Invocation{command: :auth_status}}
  end

  defp parse_command(["pr-view" | rest]) do
    PullRequest.parse_view(rest, %Invocation{command: :pr_view})
  end

  defp parse_command(["pr-create" | rest]) do
    PullRequest.parse_mutation(rest, %Invocation{command: :pr_create})
  end

  defp parse_command(["pr-edit" | rest]) do
    PullRequest.parse_mutation(rest, %Invocation{command: :pr_edit})
  end

  defp parse_command(["pr-add-label" | rest]) do
    PullRequest.parse_add_label(rest, %Invocation{command: :pr_add_label})
  end

  defp parse_command(["pr-issue-comments" | rest]) do
    Reviews.parse_issue_comments(rest, %Invocation{command: :pr_issue_comments})
  end

  defp parse_command(["pr-add-issue-comment" | rest]) do
    Reviews.parse_add_issue_comment(rest, %Invocation{command: :pr_add_issue_comment})
  end

  defp parse_command(["pr-reviews" | rest]) do
    Reviews.parse_reviews(rest, %Invocation{command: :pr_reviews})
  end

  defp parse_command(["pr-review-comments" | rest]) do
    Reviews.parse_review_comments(rest, %Invocation{command: :pr_review_comments})
  end

  defp parse_command(["pr-reply-review-comment" | rest]) do
    Reviews.parse_reply_review_comment(rest, %Invocation{command: :pr_reply_review_comment})
  end

  defp parse_command(["pr-close" | rest]) do
    PullRequest.parse_close(rest, %Invocation{command: :pr_close})
  end

  defp parse_command(["pr-merge" | rest]) do
    PullRequest.parse_merge(rest, %Invocation{command: :pr_merge})
  end

  defp parse_command(["pr-land-watch" | rest]) do
    LandWatch.parse(rest, %Invocation{command: :pr_land_watch})
  end

  defp parse_command(["pr-checks" | rest]) do
    PullRequest.parse_checks(rest, %Invocation{command: :pr_checks})
  end

  defp parse_command(["api" | rest]) do
    Api.parse(rest, %Invocation{command: :api})
  end

  defp parse_command(["run-list" | rest]) do
    Runs.parse_list(rest, %Invocation{command: :run_list})
  end

  defp parse_command(["run-view" | rest]) do
    Runs.parse_view(rest, %Invocation{command: :run_view})
  end

  defp parse_command([]) do
    {:error, Error.invalid_invocation(usage())}
  end

  defp parse_command([command | _rest]) do
    {:error, Error.invalid_invocation("Unsupported command: #{command}")}
  end

  defp usage do
    "Usage:\n  symphony repo-provider [--provider <kind>] <command> [args...]"
  end
end
