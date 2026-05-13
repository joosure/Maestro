defmodule SymphonyElixir.RepoProvider.Invocation.Reviews do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Invocation
  alias SymphonyElixir.RepoProvider.Invocation.Options

  @spec parse_issue_comments([String.t()], Invocation.t()) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse_issue_comments([], invocation), do: {:ok, invocation}

  def parse_issue_comments(["--json", fields | rest], invocation) do
    parse_issue_comments(rest, %{invocation | json_fields: Options.fields(fields)})
  end

  def parse_issue_comments(["--json"], _invocation) do
    {:error, Error.invalid_invocation("Option --json requires a value")}
  end

  def parse_issue_comments([flag, expr | rest], invocation) when flag in ["-q", "--jq"] do
    parse_issue_comments(rest, %{invocation | jq: expr})
  end

  def parse_issue_comments([flag], _invocation) when flag in ["-q", "--jq"] do
    {:error, Error.invalid_invocation("Option #{flag} requires a value")}
  end

  def parse_issue_comments([number | rest], %Invocation{number: nil} = invocation)
      when is_binary(number) do
    if String.starts_with?(number, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-issue-comments option: #{number}")}
    else
      parse_issue_comments(rest, %{invocation | number: number})
    end
  end

  def parse_issue_comments([arg | _rest], _invocation) when is_binary(arg) do
    if String.starts_with?(arg, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-issue-comments option: #{arg}")}
    else
      {:error, Error.invalid_invocation("Unexpected pr-issue-comments argument: #{arg}")}
    end
  end

  @spec parse_add_issue_comment([String.t()], Invocation.t()) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse_add_issue_comment([], %Invocation{body: nil}) do
    {:error, Error.invalid_invocation("pr-add-issue-comment requires --body or --body-file")}
  end

  def parse_add_issue_comment([], invocation), do: {:ok, invocation}

  def parse_add_issue_comment(["--body", body | rest], invocation) do
    parse_add_issue_comment(rest, %{invocation | body: body})
  end

  def parse_add_issue_comment(["--body"], _invocation) do
    {:error, Error.invalid_invocation("Option --body requires a value")}
  end

  def parse_add_issue_comment(["--body-file", path | rest], invocation) do
    with {:ok, body} <- Options.body_file(path) do
      parse_add_issue_comment(rest, %{invocation | body: body})
    end
  end

  def parse_add_issue_comment(["--body-file"], _invocation) do
    {:error, Error.invalid_invocation("Option --body-file requires a value")}
  end

  def parse_add_issue_comment([number | rest], %Invocation{number: nil} = invocation)
      when is_binary(number) do
    if String.starts_with?(number, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-add-issue-comment option: #{number}")}
    else
      parse_add_issue_comment(rest, %{invocation | number: number})
    end
  end

  def parse_add_issue_comment([arg | _rest], _invocation) when is_binary(arg) do
    if String.starts_with?(arg, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-add-issue-comment option: #{arg}")}
    else
      {:error, Error.invalid_invocation("Unexpected pr-add-issue-comment argument: #{arg}")}
    end
  end

  @spec parse_reviews([String.t()], Invocation.t()) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse_reviews([], invocation), do: {:ok, invocation}

  def parse_reviews(["--json", fields | rest], invocation) do
    parse_reviews(rest, %{invocation | json_fields: Options.fields(fields)})
  end

  def parse_reviews(["--json"], _invocation) do
    {:error, Error.invalid_invocation("Option --json requires a value")}
  end

  def parse_reviews([flag, expr | rest], invocation) when flag in ["-q", "--jq"] do
    parse_reviews(rest, %{invocation | jq: expr})
  end

  def parse_reviews([flag], _invocation) when flag in ["-q", "--jq"] do
    {:error, Error.invalid_invocation("Option #{flag} requires a value")}
  end

  def parse_reviews([number | rest], %Invocation{number: nil} = invocation)
      when is_binary(number) do
    if String.starts_with?(number, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-reviews option: #{number}")}
    else
      parse_reviews(rest, %{invocation | number: number})
    end
  end

  def parse_reviews([arg | _rest], _invocation) when is_binary(arg) do
    if String.starts_with?(arg, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-reviews option: #{arg}")}
    else
      {:error, Error.invalid_invocation("Unexpected pr-reviews argument: #{arg}")}
    end
  end

  @spec parse_review_comments([String.t()], Invocation.t()) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse_review_comments([], invocation), do: {:ok, invocation}

  def parse_review_comments(["--json", fields | rest], invocation) do
    parse_review_comments(rest, %{invocation | json_fields: Options.fields(fields)})
  end

  def parse_review_comments(["--json"], _invocation) do
    {:error, Error.invalid_invocation("Option --json requires a value")}
  end

  def parse_review_comments([flag, expr | rest], invocation) when flag in ["-q", "--jq"] do
    parse_review_comments(rest, %{invocation | jq: expr})
  end

  def parse_review_comments([flag], _invocation) when flag in ["-q", "--jq"] do
    {:error, Error.invalid_invocation("Option #{flag} requires a value")}
  end

  def parse_review_comments([number | rest], %Invocation{number: nil} = invocation)
      when is_binary(number) do
    if String.starts_with?(number, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-review-comments option: #{number}")}
    else
      parse_review_comments(rest, %{invocation | number: number})
    end
  end

  def parse_review_comments([arg | _rest], _invocation) when is_binary(arg) do
    if String.starts_with?(arg, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-review-comments option: #{arg}")}
    else
      {:error, Error.invalid_invocation("Unexpected pr-review-comments argument: #{arg}")}
    end
  end

  @spec parse_reply_review_comment([String.t()], Invocation.t()) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse_reply_review_comment([], %Invocation{comment_id: nil}) do
    {:error, Error.invalid_invocation("pr-reply-review-comment requires a comment id")}
  end

  def parse_reply_review_comment([], %Invocation{body: nil}) do
    {:error, Error.invalid_invocation("pr-reply-review-comment requires --body or --body-file")}
  end

  def parse_reply_review_comment([], invocation), do: {:ok, invocation}

  def parse_reply_review_comment(["--body", body | rest], invocation) do
    parse_reply_review_comment(rest, %{invocation | body: body})
  end

  def parse_reply_review_comment(["--body"], _invocation) do
    {:error, Error.invalid_invocation("Option --body requires a value")}
  end

  def parse_reply_review_comment(["--body-file", path | rest], invocation) do
    with {:ok, body} <- Options.body_file(path) do
      parse_reply_review_comment(rest, %{invocation | body: body})
    end
  end

  def parse_reply_review_comment(["--body-file"], _invocation) do
    {:error, Error.invalid_invocation("Option --body-file requires a value")}
  end

  def parse_reply_review_comment(
        [comment_id | rest],
        %Invocation{comment_id: nil} = invocation
      )
      when is_binary(comment_id) do
    if String.starts_with?(comment_id, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-reply-review-comment option: #{comment_id}")}
    else
      parse_reply_review_comment(rest, %{invocation | comment_id: comment_id})
    end
  end

  def parse_reply_review_comment([number | rest], %Invocation{number: nil} = invocation)
      when is_binary(number) do
    if String.starts_with?(number, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-reply-review-comment option: #{number}")}
    else
      parse_reply_review_comment(rest, %{invocation | number: number})
    end
  end

  def parse_reply_review_comment([arg | _rest], _invocation) when is_binary(arg) do
    if String.starts_with?(arg, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-reply-review-comment option: #{arg}")}
    else
      {:error, Error.invalid_invocation("Unexpected pr-reply-review-comment argument: #{arg}")}
    end
  end
end
