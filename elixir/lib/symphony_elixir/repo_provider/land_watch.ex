defmodule SymphonyElixir.RepoProvider.LandWatch do
  @moduledoc false

  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.LandWatch.{Checks, PRState, Reviews}

  @default_poll_ms 10_000
  @default_checks_appear_timeout_ms 120_000
  @default_max_provider_retries 5
  @default_provider_backoff_ms 2_000

  @internal_opt_keys [
    :checks_appear_timeout_ms,
    :env,
    :max_provider_retries,
    :number,
    :poll_ms,
    :provider_backoff_ms,
    :pr_checks_fn,
    :pr_issue_comments_fn,
    :pr_review_comments_fn,
    :pr_reviews_fn,
    :pr_view_fn,
    :sleep_fn
  ]

  @type watch_result :: {:ok, String.t(), non_neg_integer()} | {:error, Error.t()}

  @spec watch(map(), keyword()) :: watch_result()
  def watch(repo_config, opts \\ []) when is_map(repo_config) and is_list(opts) do
    with {:ok, pr} <- fetch_pr_info(repo_config, opts) do
      output = ["Waiting for review feedback...\n", "Waiting for CI checks...\n"]

      if PRState.merge_conflicting?(pr) do
        halt(output, conflict_message(), 5)
      else
        settings = Reviews.settings_from_env(env(opts))

        loop(%{
          repo_config: repo_config,
          opts: opts,
          settings: settings,
          pr_number: to_string(pr.number),
          head_sha: pr.head_sha,
          empty_checks_ms: 0,
          output: output
        })
      end
    end
  end

  defp loop(state) do
    with {:ok, current_pr} <- fetch_pr_info(state.repo_config, state.opts),
         :ok <- verify_pr_head(current_pr, state.head_sha),
         {:ok, issue_comments, review_comments, reviews} <-
           fetch_review_context(state.repo_config, state.pr_number, state.opts),
         :ok <- verify_review_context(issue_comments, review_comments, reviews, state.settings),
         {:ok, check_runs} <- fetch_check_runs(state.repo_config, state.pr_number, state.opts) do
      handle_check_runs(state, check_runs)
    else
      {:halt, message, exit_code} -> halt(state.output, message, exit_code)
      {:blocked, exit_code, message} -> halt(state.output, message, exit_code)
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.normalize(repo_provider_kind(state.repo_config), :pr_land_watch, reason)}
    end
  end

  defp handle_check_runs(state, []) do
    empty_checks_ms = state.empty_checks_ms + poll_ms(state.opts)

    timeout_ms = checks_appear_timeout_ms(state.opts)

    if empty_checks_ms >= timeout_ms do
      halt(state.output, "No checks detected after #{format_seconds(timeout_ms)}; check CI configuration\n", 3)
    else
      sleep(state.opts)
      loop(%{state | empty_checks_ms: empty_checks_ms})
    end
  end

  defp handle_check_runs(state, check_runs) do
    case Checks.summarize(check_runs) do
      %{failed?: true, failures: failures} ->
        failure_lines = Enum.map(failures, &["- ", &1, "\n"])
        halt(state.output, ["Checks failed:\n", failure_lines], 3)

      %{pending?: false} ->
        halt(state.output, "Checks passed\n", 0)

      _summary ->
        sleep(state.opts)
        loop(%{state | empty_checks_ms: 0})
    end
  end

  defp fetch_pr_info(repo_config, opts) do
    number = opts |> Keyword.get(:number) |> present_string()
    provider_opts = opts |> provider_opts() |> maybe_put(:number, number)
    pr_view_fn = Keyword.get(opts, :pr_view_fn, &RepoProvider.pr_view/2)

    with {:ok, payload} <- provider_call(opts, fn -> pr_view_fn.(repo_config, provider_opts) end),
         {:ok, %PRState{} = pr} <- PRState.from_payload(payload) do
      {:ok, pr}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.normalize(repo_provider_kind(repo_config), :pr_view, reason)}
    end
  end

  defp fetch_review_context(repo_config, pr_number, opts) do
    provider_opts = opts |> provider_opts() |> Keyword.put(:number, pr_number)

    with {:ok, issue_comments} <-
           provider_call(opts, fn ->
             Keyword.get(opts, :pr_issue_comments_fn, &RepoProvider.pr_issue_comments/2).(repo_config, provider_opts)
           end),
         {:ok, issue_comments} <- list_payload(issue_comments, :pr_issue_comments),
         {:ok, review_comments} <-
           provider_call(opts, fn ->
             Keyword.get(opts, :pr_review_comments_fn, &RepoProvider.pr_review_comments/2).(repo_config, provider_opts)
           end),
         {:ok, review_comments} <- list_payload(review_comments, :pr_review_comments),
         {:ok, reviews} <-
           provider_call(opts, fn ->
             Keyword.get(opts, :pr_reviews_fn, &RepoProvider.pr_reviews/2).(repo_config, provider_opts)
           end),
         {:ok, reviews} <- list_payload(reviews, :pr_reviews) do
      {:ok, issue_comments, review_comments, reviews}
    end
  end

  defp fetch_check_runs(repo_config, pr_number, opts) do
    provider_opts = opts |> provider_opts() |> Keyword.put(:number, pr_number)

    with {:ok, check_runs} <-
           provider_call(opts, fn ->
             Keyword.get(opts, :pr_checks_fn, &RepoProvider.pr_checks/2).(repo_config, provider_opts)
           end),
         {:ok, check_runs} <- list_payload(check_runs, :pr_checks) do
      {:ok, check_runs}
    end
  end

  defp verify_pr_head(%PRState{} = pr, original_head_sha) do
    cond do
      PRState.merge_conflicting?(pr) ->
        {:halt, conflict_message(), 5}

      pr.head_sha != original_head_sha ->
        {:halt, "PR head updated; pull/amend/force-push to retrigger CI\n", 4}

      true ->
        :ok
    end
  end

  defp verify_review_context(issue_comments, review_comments, reviews, settings) do
    Reviews.evaluate(issue_comments, review_comments, reviews, settings)
  end

  defp provider_call(opts, fun) when is_function(fun, 0) do
    provider_call(opts, fun, 1, provider_backoff_ms(opts))
  end

  defp provider_call(opts, fun, attempt, delay_ms) do
    case fun.() do
      {:error, %Error{} = error} ->
        if Error.retryable?(error) and attempt < max_provider_retries(opts) do
          sleep(opts, delay_ms)
          provider_call(opts, fun, attempt + 1, min(delay_ms * 2, max_provider_delay_ms(opts)))
        else
          {:error, error}
        end

      {:error, reason} ->
        {:error, reason}

      {:ok, payload} ->
        {:ok, payload}
    end
  end

  defp halt(output, message, exit_code) do
    {:ok, IO.iodata_to_binary([output, message]), exit_code}
  end

  defp conflict_message do
    "PR has merge conflicts. Resolve/rebase against the base branch and push before running pr-land-watch again.\n"
  end

  defp provider_opts(opts), do: Keyword.drop(opts, @internal_opt_keys)

  defp list_payload(payload, _operation) when is_list(payload), do: {:ok, payload}

  defp list_payload(_payload, operation) do
    {:error, {:invalid_repo_provider_payload, operation, :expected_list}}
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp present_string(nil), do: nil
  defp present_string(value), do: value |> to_string() |> String.trim() |> blank_to_nil()

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp env(opts) do
    case Keyword.get(opts, :env) do
      nil -> System.get_env()
      env when is_map(env) -> env
      env when is_list(env) -> Map.new(env)
    end
  end

  defp repo_provider_kind(repo_config), do: RepoProvider.current_kind(repo_config)

  defp poll_ms(opts), do: Keyword.get(opts, :poll_ms, @default_poll_ms)

  defp checks_appear_timeout_ms(opts) do
    Keyword.get(opts, :checks_appear_timeout_ms, @default_checks_appear_timeout_ms)
  end

  defp format_seconds(milliseconds) when rem(milliseconds, 1_000) == 0 do
    "#{div(milliseconds, 1_000)}s"
  end

  defp format_seconds(milliseconds), do: "#{milliseconds}ms"

  defp max_provider_retries(opts), do: Keyword.get(opts, :max_provider_retries, @default_max_provider_retries)
  defp provider_backoff_ms(opts), do: Keyword.get(opts, :provider_backoff_ms, @default_provider_backoff_ms)

  defp max_provider_delay_ms(opts) do
    provider_backoff_ms(opts) * power_of_two(max_provider_retries(opts) - 1)
  end

  defp power_of_two(exponent) when exponent <= 0, do: 1
  defp power_of_two(exponent), do: Enum.reduce(1..exponent, 1, fn _step, acc -> acc * 2 end)

  defp sleep(opts), do: sleep(opts, poll_ms(opts))

  defp sleep(opts, milliseconds) do
    Keyword.get(opts, :sleep_fn, &Process.sleep/1).(milliseconds)
  end
end
