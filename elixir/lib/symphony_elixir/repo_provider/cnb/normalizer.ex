defmodule SymphonyElixir.RepoProvider.CNB.Normalizer do
  @moduledoc """
  Data normalization layer for the CNB repo-provider adapter.

  Transforms raw CNB API payloads into the canonical format expected
  by the `RepoProvider` facade. All functions are pure data transforms
  with no side-effects.
  """

  alias SymphonyElixir.RepoProvider.CNB.Normalizer.{Checks, Discussion, Errors, Pull, Run, Values}
  alias SymphonyElixir.RepoProvider.Error

  @spec normalize_pull(map(), String.t(), map()) :: map()
  defdelegate normalize_pull(repo, repository, pull), to: Pull

  @spec normalized_pull_state(map(), String.t()) :: String.t()
  defdelegate normalized_pull_state(pull, mergeable_state), to: Pull

  @spec merged_by_present?(map()) :: boolean()
  defdelegate merged_by_present?(pull), to: Pull

  @spec normalize_run_summary(map()) :: map()
  defdelegate normalize_run_summary(build), to: Run

  @spec normalize_pipelines(map() | term()) :: list(map())
  defdelegate normalize_pipelines(pipelines_status), to: Run

  @spec normalize_stages(list() | term()) :: list(map())
  defdelegate normalize_stages(stages), to: Run

  @spec normalize_execution_state(term()) :: {String.t(), String.t() | nil}
  defdelegate normalize_execution_state(raw_status), to: Run

  @spec normalize_check_payload(map()) :: list(map())
  defdelegate normalize_check_payload(payload), to: Checks

  @spec normalize_check_run(map()) :: map()
  defdelegate normalize_check_run(status), to: Checks

  @spec map_check_conclusion(String.t()) :: String.t()
  defdelegate map_check_conclusion(state), to: Checks

  @spec normalize_issue_comment(map()) :: map()
  defdelegate normalize_issue_comment(comment), to: Discussion

  @spec normalize_review(map()) :: map()
  defdelegate normalize_review(review), to: Discussion

  @spec normalize_review_comment(map()) :: map()
  defdelegate normalize_review_comment(comment), to: Discussion

  @spec normalize_user(map() | term()) :: map()
  defdelegate normalize_user(user), to: Discussion

  @spec map_runtime_error(term()) :: Error.t()
  defdelegate map_runtime_error(reason), to: Errors

  @spec cnb_build_scope_error?(String.t(), map()) :: boolean()
  defdelegate cnb_build_scope_error?(url, body), to: Errors

  @spec field_value(map(), String.t(), atom()) :: term()
  defdelegate field_value(map, string_key, atom_key), to: Values

  @spec json_id(term()) :: term()
  defdelegate json_id(value), to: Values

  @spec slice_page(list(), pos_integer(), pos_integer()) :: list()
  defdelegate slice_page(items, page, per_page), to: Values

  @spec expect_list(term(), atom()) :: {:ok, list()} | {:error, term()}
  defdelegate expect_list(payload, context), to: Values

  @spec expect_map(term(), atom()) :: {:ok, map()} | {:error, term()}
  defdelegate expect_map(payload, context), to: Values

  @spec build_log_items(map()) :: {:ok, list(map())} | {:error, term()}
  defdelegate build_log_items(payload), to: Run

  @spec review_id_values(map()) :: list()
  defdelegate review_id_values(review), to: Discussion

  @spec review_comment_review_id(map(), String.t()) :: {:ok, term()} | {:error, Error.t()}
  defdelegate review_comment_review_id(comment, reply_to), to: Discussion

  @spec maybe_append_line(list(), String.t(), term()) :: list()
  defdelegate maybe_append_line(lines, label, value), to: Run

  @spec pull_number(map()) :: term()
  defdelegate pull_number(pull), to: Pull

  @spec pull_title(map()) :: String.t()
  defdelegate pull_title(pull), to: Pull

  @spec pull_body(map()) :: String.t()
  defdelegate pull_body(pull), to: Pull

  @spec pull_head_branch(map()) :: String.t() | nil
  defdelegate pull_head_branch(pull), to: Pull

  @spec pull_head_sha(map()) :: String.t() | nil
  defdelegate pull_head_sha(pull), to: Pull

  @spec pull_base_branch(map()) :: String.t() | nil
  defdelegate pull_base_branch(pull), to: Pull

  @spec pull_wip?(map()) :: boolean()
  defdelegate pull_wip?(pull), to: Pull

  @spec pull_state_priority(map()) :: non_neg_integer()
  defdelegate pull_state_priority(pull), to: Pull

  @spec pull_head_ref(map()) :: String.t() | nil
  defdelegate pull_head_ref(pull), to: Pull
end
