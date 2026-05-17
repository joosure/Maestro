defmodule SymphonyElixir.RepoProvider.CommandNames do
  @moduledoc """
  Stable command names for the external `symphony repo-provider` CLI contract.
  """

  @current_kind "current-kind"
  @auth_status "auth-status"
  @pr_view "pr-view"
  @pr_create "pr-create"
  @pr_edit "pr-edit"
  @pr_add_label "pr-add-label"
  @pr_issue_comments "pr-issue-comments"
  @pr_add_issue_comment "pr-add-issue-comment"
  @pr_reviews "pr-reviews"
  @pr_review_comments "pr-review-comments"
  @pr_reply_review_comment "pr-reply-review-comment"
  @pr_close "pr-close"
  @pr_merge "pr-merge"
  @pr_land_watch "pr-land-watch"
  @pr_checks "pr-checks"
  @api "api"
  @run_list "run-list"
  @run_view "run-view"
  @run_view_log "run-view-log"

  @spec current_kind() :: String.t()
  def current_kind, do: @current_kind

  @spec auth_status() :: String.t()
  def auth_status, do: @auth_status

  @spec pr_view() :: String.t()
  def pr_view, do: @pr_view

  @spec pr_create() :: String.t()
  def pr_create, do: @pr_create

  @spec pr_edit() :: String.t()
  def pr_edit, do: @pr_edit

  @spec pr_add_label() :: String.t()
  def pr_add_label, do: @pr_add_label

  @spec pr_issue_comments() :: String.t()
  def pr_issue_comments, do: @pr_issue_comments

  @spec pr_add_issue_comment() :: String.t()
  def pr_add_issue_comment, do: @pr_add_issue_comment

  @spec pr_reviews() :: String.t()
  def pr_reviews, do: @pr_reviews

  @spec pr_review_comments() :: String.t()
  def pr_review_comments, do: @pr_review_comments

  @spec pr_reply_review_comment() :: String.t()
  def pr_reply_review_comment, do: @pr_reply_review_comment

  @spec pr_close() :: String.t()
  def pr_close, do: @pr_close

  @spec pr_merge() :: String.t()
  def pr_merge, do: @pr_merge

  @spec pr_land_watch() :: String.t()
  def pr_land_watch, do: @pr_land_watch

  @spec pr_checks() :: String.t()
  def pr_checks, do: @pr_checks

  @spec api() :: String.t()
  def api, do: @api

  @spec run_list() :: String.t()
  def run_list, do: @run_list

  @spec run_view() :: String.t()
  def run_view, do: @run_view

  @spec run_view_log() :: String.t()
  def run_view_log, do: @run_view_log

  @spec all() :: [String.t()]
  def all do
    [
      @current_kind,
      @auth_status,
      @pr_view,
      @pr_create,
      @pr_edit,
      @pr_add_label,
      @pr_issue_comments,
      @pr_add_issue_comment,
      @pr_reviews,
      @pr_review_comments,
      @pr_reply_review_comment,
      @pr_close,
      @pr_merge,
      @pr_land_watch,
      @pr_checks,
      @api,
      @run_list,
      @run_view
    ]
  end
end
