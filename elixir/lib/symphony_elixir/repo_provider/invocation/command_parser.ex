defmodule SymphonyElixir.RepoProvider.Invocation.CommandParser do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CommandNames
  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Invocation
  alias SymphonyElixir.RepoProvider.Invocation.{Api, LandWatch, PullRequest, Reviews, Runs}

  @current_kind_command CommandNames.current_kind()
  @auth_status_command CommandNames.auth_status()
  @pr_view_command CommandNames.pr_view()
  @pr_create_command CommandNames.pr_create()
  @pr_edit_command CommandNames.pr_edit()
  @pr_add_label_command CommandNames.pr_add_label()
  @pr_issue_comments_command CommandNames.pr_issue_comments()
  @pr_add_issue_comment_command CommandNames.pr_add_issue_comment()
  @pr_reviews_command CommandNames.pr_reviews()
  @pr_review_comments_command CommandNames.pr_review_comments()
  @pr_reply_review_comment_command CommandNames.pr_reply_review_comment()
  @pr_close_command CommandNames.pr_close()
  @pr_merge_command CommandNames.pr_merge()
  @pr_land_watch_command CommandNames.pr_land_watch()
  @pr_checks_command CommandNames.pr_checks()
  @api_command CommandNames.api()
  @run_list_command CommandNames.run_list()
  @run_view_command CommandNames.run_view()

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

  defp parse_command([@current_kind_command]) do
    {:ok, %Invocation{command: :current_kind}}
  end

  defp parse_command([@auth_status_command]) do
    {:ok, %Invocation{command: :auth_status}}
  end

  defp parse_command([@pr_view_command | rest]) do
    PullRequest.parse_view(rest, %Invocation{command: :pr_view})
  end

  defp parse_command([@pr_create_command | rest]) do
    PullRequest.parse_mutation(rest, %Invocation{command: :pr_create})
  end

  defp parse_command([@pr_edit_command | rest]) do
    PullRequest.parse_mutation(rest, %Invocation{command: :pr_edit})
  end

  defp parse_command([@pr_add_label_command | rest]) do
    PullRequest.parse_add_label(rest, %Invocation{command: :pr_add_label})
  end

  defp parse_command([@pr_issue_comments_command | rest]) do
    Reviews.parse_issue_comments(rest, %Invocation{command: :pr_issue_comments})
  end

  defp parse_command([@pr_add_issue_comment_command | rest]) do
    Reviews.parse_add_issue_comment(rest, %Invocation{command: :pr_add_issue_comment})
  end

  defp parse_command([@pr_reviews_command | rest]) do
    Reviews.parse_reviews(rest, %Invocation{command: :pr_reviews})
  end

  defp parse_command([@pr_review_comments_command | rest]) do
    Reviews.parse_review_comments(rest, %Invocation{command: :pr_review_comments})
  end

  defp parse_command([@pr_reply_review_comment_command | rest]) do
    Reviews.parse_reply_review_comment(rest, %Invocation{command: :pr_reply_review_comment})
  end

  defp parse_command([@pr_close_command | rest]) do
    PullRequest.parse_close(rest, %Invocation{command: :pr_close})
  end

  defp parse_command([@pr_merge_command | rest]) do
    PullRequest.parse_merge(rest, %Invocation{command: :pr_merge})
  end

  defp parse_command([@pr_land_watch_command | rest]) do
    LandWatch.parse(rest, %Invocation{command: :pr_land_watch})
  end

  defp parse_command([@pr_checks_command | rest]) do
    PullRequest.parse_checks(rest, %Invocation{command: :pr_checks})
  end

  defp parse_command([@api_command | rest]) do
    Api.parse(rest, %Invocation{command: :api})
  end

  defp parse_command([@run_list_command | rest]) do
    Runs.parse_list(rest, %Invocation{command: :run_list})
  end

  defp parse_command([@run_view_command | rest]) do
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
