defmodule SymphonyElixir.Tracker.Tapd.Client do
  @moduledoc """
  Restricted TAPD HTTP client for Symphony's supported Stories subset.
  """

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker.Tapd.Client.{Reader, Request, Response, Writer}

  @spec fetch_candidate_issues(map()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues(tracker) when is_map(tracker), do: Reader.fetch_candidate_issues(tracker)

  @spec fetch_issues_by_states([String.t()], map()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names, tracker) when is_list(state_names) and is_map(tracker) do
    Reader.fetch_issues_by_states(state_names, tracker)
  end

  @spec fetch_issue_states_by_ids([String.t()], map()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids, tracker) when is_list(issue_ids) and is_map(tracker) do
    Reader.fetch_issue_states_by_ids(issue_ids, tracker)
  end

  @spec request(String.t(), String.t(), map() | nil, keyword()) :: {:ok, map()} | {:error, term()}
  def request(method, path, params \\ %{}, opts \\ [])
      when is_binary(method) and is_binary(path) and is_list(opts),
      do: Request.request(method, path, params, opts)

  @spec fetch_stories_by_status([String.t()], keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_stories_by_status(state_names, opts \\ [])
      when is_list(state_names) and is_list(opts),
      do: Reader.fetch_stories_by_status(state_names, opts)

  @spec fetch_stories_by_ids([String.t()], keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_stories_by_ids(issue_ids, opts \\ []) when is_list(issue_ids) and is_list(opts),
    do: Reader.fetch_stories_by_ids(issue_ids, opts)

  @spec create_story_comment(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_story_comment(story_id, description, opts \\ [])
      when is_binary(story_id) and is_binary(description) and is_list(opts),
      do: Writer.create_story_comment(story_id, description, opts)

  @spec update_story_status(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_story_status(story_id, status, opts \\ [])
      when is_binary(story_id) and is_binary(status) and is_list(opts),
      do: Writer.update_story_status(story_id, status, opts)

  @spec tapd_success?(term()) :: boolean()
  def tapd_success?(body), do: Response.tapd_success?(body)

  @spec decode_success_envelope(String.t(), term()) :: {:ok, term()} | {:error, term()}
  def decode_success_envelope(path, body) when is_binary(path), do: Response.decode_success_envelope(path, body)

  @spec tapd_error_reason(term()) :: term()
  def tapd_error_reason(reason), do: Response.tapd_error_reason(reason)
end
