defmodule SymphonyElixir.RepoProvider.Invocation do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Invocation.CommandParser

  defstruct [
    :provider_override,
    :command,
    :number,
    :comment_id,
    :label,
    :comment,
    :title,
    :body,
    :base,
    :head,
    :subject,
    :branch,
    :run_id,
    :api_endpoint,
    api_method: "GET",
    api_fields: %{},
    poll_ms: nil,
    checks_appear_timeout_ms: nil,
    json?: false,
    watch?: false,
    json_fields: nil,
    jq: nil,
    limit: 20,
    log?: false,
    merge_style: "merge"
  ]

  @type t :: %__MODULE__{
          provider_override: nil | String.t(),
          command:
            :current_kind
            | :auth_status
            | :pr_view
            | :pr_create
            | :pr_edit
            | :pr_add_label
            | :pr_issue_comments
            | :pr_add_issue_comment
            | :pr_reviews
            | :pr_review_comments
            | :pr_reply_review_comment
            | :pr_close
            | :pr_merge
            | :pr_land_watch
            | :pr_checks
            | :api
            | :run_list
            | :run_view,
          number: nil | String.t(),
          comment_id: nil | String.t(),
          label: nil | String.t(),
          comment: nil | String.t(),
          title: nil | String.t(),
          body: nil | String.t(),
          base: nil | String.t(),
          head: nil | String.t(),
          subject: nil | String.t(),
          branch: nil | String.t(),
          run_id: nil | String.t(),
          api_endpoint: nil | String.t(),
          api_method: String.t(),
          api_fields: map(),
          poll_ms: nil | pos_integer(),
          checks_appear_timeout_ms: nil | pos_integer(),
          json?: boolean(),
          watch?: boolean(),
          json_fields: nil | [String.t()],
          jq: nil | String.t(),
          limit: pos_integer(),
          log?: boolean(),
          merge_style: String.t()
        }

  @spec parse([String.t()]) :: {:ok, t()} | {:error, Error.t()}
  def parse(argv) when is_list(argv), do: CommandParser.parse(argv)
end
