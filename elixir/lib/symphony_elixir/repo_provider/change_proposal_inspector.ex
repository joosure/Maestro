defmodule SymphonyElixir.RepoProvider.ChangeProposalInspector do
  @moduledoc false

  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.RepoProvider.Config, as: RepoConfig
  alias SymphonyElixir.RepoProvider.Error, as: RepoProviderError
  alias SymphonyElixir.RepoProvider.LandWatch.{Checks, Reviews}
  alias SymphonyElixir.Workflow.ChangeProposalReconciliation.Facts

  @provider_state_by_name %{
    "merged" => :merged,
    "open" => :open,
    "closed" => :closed
  }

  @spec facts(map(), map() | nil, keyword()) :: Facts.t()
  def facts(repo_config, target, opts \\ [])

  def facts(repo_config, nil, _opts) when is_map(repo_config) do
    missing_facts(repo_config, %{})
  end

  def facts(repo_config, target, opts) when is_map(repo_config) and is_map(target) and is_list(opts) do
    provider_opts = provider_target_opts(target)

    case provider_call(:pr_view, repo_config, provider_opts, opts) do
      {:ok, pr_payload} when is_map(pr_payload) ->
        inspect_context(repo_config, target, pr_payload, opts)

      {:error, reason} ->
        if change_proposal_not_found?(reason) do
          missing_facts(repo_config, target)
        else
          error_facts(repo_config, :pr_view, target, reason)
        end

      {:ok, payload} ->
        error_facts(repo_config, :pr_view, target, {:invalid_repo_provider_payload, :pr_view, payload})
    end
  end

  defp inspect_context(repo_config, target, pr_payload, opts) do
    provider_opts = provider_target_opts(pr_payload, target)

    with {:ok, issue_comments} <- provider_list(:pr_issue_comments, repo_config, provider_opts, opts),
         {:ok, review_comments} <- provider_list(:pr_review_comments, repo_config, provider_opts, opts),
         {:ok, reviews} <- provider_list(:pr_reviews, repo_config, provider_opts, opts),
         {:ok, checks} <- provider_list(:pr_checks, repo_config, provider_opts, opts) do
      provider_payload_facts(
        repo_config,
        target,
        pr_payload,
        issue_comments,
        review_comments,
        reviews,
        checks,
        opts
      )
    else
      {:error, {operation, reason}} ->
        error_facts(repo_config, operation, target, reason)
    end
  end

  defp missing_facts(repo_config, target) when is_map(repo_config) and is_map(target) do
    repo_config
    |> base_attrs(target)
    |> Facts.new!()
  end

  defp error_facts(repo_config, operation, target, reason)
       when is_map(repo_config) and is_atom(operation) and is_map(target) do
    error = RepoProviderError.normalize(repo_config, operation, reason)

    repo_config
    |> base_attrs(target)
    |> Map.merge(%{
      error: error,
      retryable?: RepoProviderError.retryable?(error),
      provider_state: :unknown
    })
    |> Facts.new!()
  end

  defp provider_payload_facts(
         repo_config,
         target,
         pr_payload,
         issue_comments,
         review_comments,
         reviews,
         check_runs,
         opts
       )
       when is_map(repo_config) and is_map(target) and is_map(pr_payload) and is_list(issue_comments) and
              is_list(review_comments) and is_list(reviews) and is_list(check_runs) and is_list(opts) do
    settings = Reviews.settings_from_env(Keyword.get(opts, :env, System.get_env()))

    repo_config
    |> base_attrs(target)
    |> Map.merge(%{
      number: field_value(pr_payload, "number"),
      url: field_value(pr_payload, "url"),
      branch: field_value(pr_payload, "headRefName") || target_value(target, :branch),
      head_sha: field_value(pr_payload, "headRefOid"),
      provider_state: provider_state(pr_payload),
      review_summary: review_summary(reviews),
      check_summary: check_summary(check_runs),
      mergeability_summary: mergeability_summary(pr_payload),
      unresolved_actionable_feedback?: unresolved_actionable_feedback?(issue_comments, review_comments, settings)
    })
    |> Facts.new!()
  end

  defp change_proposal_not_found?(%RepoProviderError{code: code}) do
    code in [
      :cnb_pull_not_found,
      :cnb_pull_not_found_for_branch,
      :cnb_pull_not_found_for_sha,
      :github_pr_not_found
    ]
  end

  defp change_proposal_not_found?(reason) do
    reason
    |> RepoProviderError.normalize(nil, :pr_view)
    |> change_proposal_not_found?()
  end

  defp base_attrs(repo_config, target) do
    %{
      provider_kind: RepoProvider.current_kind(repo_config),
      repository: RepoConfig.repository(repo_config),
      number: target_value(target, :number),
      url: target_value(target, :url),
      branch: target_value(target, :branch),
      observed_at: DateTime.utc_now()
    }
  end

  defp provider_call(operation, repo, provider_opts, opts)
       when is_atom(operation) and is_map(repo) and is_list(provider_opts) do
    operation
    |> provider_fun(opts)
    |> then(& &1.(repo, provider_opts))
    |> normalize_provider_result(operation)
  end

  defp provider_list(operation, repo, provider_opts, opts) do
    case provider_call(operation, repo, provider_opts, opts) do
      {:ok, payload} when is_list(payload) -> {:ok, payload}
      {:ok, payload} -> {:error, {operation, {:invalid_repo_provider_payload, operation, payload}}}
      {:error, reason} -> {:error, {operation, reason}}
    end
  end

  defp provider_fun(:pr_view, opts), do: Keyword.get(opts, :pr_view_fn, &RepoProvider.pr_view/2)
  defp provider_fun(:pr_issue_comments, opts), do: Keyword.get(opts, :pr_issue_comments_fn, &RepoProvider.pr_issue_comments/2)
  defp provider_fun(:pr_review_comments, opts), do: Keyword.get(opts, :pr_review_comments_fn, &RepoProvider.pr_review_comments/2)
  defp provider_fun(:pr_reviews, opts), do: Keyword.get(opts, :pr_reviews_fn, &RepoProvider.pr_reviews/2)
  defp provider_fun(:pr_checks, opts), do: Keyword.get(opts, :pr_checks_fn, &RepoProvider.pr_checks/2)

  defp normalize_provider_result({:ok, payload}, _operation), do: {:ok, payload}
  defp normalize_provider_result({:error, reason}, _operation), do: {:error, reason}
  defp normalize_provider_result(:unsupported, operation), do: {:error, {:unsupported_repo_provider_operation, operation}}
  defp normalize_provider_result(other, operation), do: {:error, {:invalid_repo_provider_result, operation, other}}

  defp provider_target_opts(target) when is_map(target) do
    case target_value(target, :number) || target_value(target, :url) || target_value(target, :branch) do
      value when is_binary(value) -> [number: value]
      value when is_integer(value) -> [number: Integer.to_string(value)]
      _value -> []
    end
  end

  defp provider_target_opts(pr_payload, target) when is_map(pr_payload) and is_map(target) do
    provider_target_opts(%{
      number: present_string(field_value(pr_payload, "number")) || target_value(target, :number),
      url: target_value(target, :url),
      branch: target_value(target, :branch)
    })
  end

  defp provider_state(payload) when is_map(payload) do
    merged? = field_value(payload, "merged") == true or present?(field_value(payload, "mergedAt"))

    cond do
      merged? ->
        :merged

      true ->
        @provider_state_by_name
        |> Map.get(payload |> field_value("state") |> normalize_token(), :unknown)
    end
  end

  defp review_summary(reviews) when is_list(reviews) do
    latest_reviews = latest_review_by_user(reviews)

    cond do
      Enum.any?(latest_reviews, &(review_state(&1) == "changes_requested")) ->
        :changes_requested

      Enum.any?(latest_reviews, &(review_state(&1) == "approved")) ->
        :approved

      true ->
        :pending
    end
  end

  defp check_summary([]), do: :absent

  defp check_summary(check_runs) when is_list(check_runs) do
    case Checks.summarize(check_runs) do
      %{failed?: true} -> :failing
      %{pending?: true} -> :pending
      %{pending?: false} -> :passing
    end
  end

  defp mergeability_summary(payload) when is_map(payload) do
    mergeable = payload |> field_value("mergeable") |> normalize_token()
    merge_state = payload |> field_value("mergeStateStatus") |> normalize_token()

    cond do
      mergeable == "conflicting" or merge_state == "dirty" ->
        :conflicting

      merge_state in ["blocked", "draft"] ->
        :blocked

      mergeable == "mergeable" and merge_state in ["", "clean", "has_hooks", "unstable", "unknown"] ->
        :mergeable

      merge_state in ["clean", "has_hooks", "unstable"] ->
        :mergeable

      true ->
        :unknown
    end
  end

  defp unresolved_actionable_feedback?(issue_comments, review_comments, settings) do
    Reviews.filter_human_issue_comments(issue_comments, settings) != [] or
      Reviews.filter_agent_review_issue_comments(issue_comments, settings) != [] or
      Reviews.filter_human_review_comments(review_comments, settings) != []
  end

  defp latest_review_by_user(reviews) do
    reviews
    |> Enum.reduce(%{}, fn review, latest ->
      user = review |> field_value("user") |> user_login()

      cond do
        user == "" -> latest
        replace_review?(review, Map.get(latest, user)) -> Map.put(latest, user, review)
        true -> latest
      end
    end)
    |> Map.values()
  end

  defp replace_review?(_review, nil), do: true

  defp replace_review?(review, existing_review) do
    case {review_time(review), review_time(existing_review)} do
      {%DateTime{} = left, %DateTime{} = right} -> DateTime.compare(left, right) == :gt
      {%DateTime{}, nil} -> true
      _other -> false
    end
  end

  defp review_state(review) when is_map(review) do
    review
    |> field_value("state")
    |> normalize_token()
  end

  defp review_time(review) when is_map(review) do
    case field_value(review, "submitted_at") || field_value(review, "created_at") do
      value when is_binary(value) -> parse_time(value)
      _value -> nil
    end
  end

  defp parse_time(value) when is_binary(value) do
    value
    |> String.replace_suffix("Z", "+00:00")
    |> DateTime.from_iso8601()
    |> case do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp user_login(user) when is_map(user) do
    user
    |> field_value("login")
    |> to_string()
  end

  defp user_login(_user), do: ""

  defp target_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp target_value(_map, _key), do: nil

  defp field_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp field_value(_map, _key), do: nil

  defp map_get_existing_atom(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp normalize_token(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_token(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_token()
  defp normalize_token(_value), do: ""

  defp present_string(value) when is_integer(value), do: Integer.to_string(value)

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_string(_value), do: nil

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)
end
