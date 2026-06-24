defmodule SymphonyElixir.RepoProvider.Capabilities do
  @moduledoc """
  Repo-provider capability strings.

  RepoProvider owns both provider logical capabilities and typed-tool
  capabilities for remote change-proposal, review, check, and merge surfaces.
  """

  @behaviour SymphonyElixir.Capability.Source

  @change_proposal_snapshot "repo.change_proposal_snapshot"
  @create_or_update_change_proposal "repo.create_or_update_change_proposal"
  @read_change_proposal_discussion "repo.read_change_proposal_discussion"
  @add_change_proposal_comment "repo.add_change_proposal_comment"
  @submit_change_proposal_review "repo.submit_change_proposal_review"
  @reply_change_proposal_review_comment "repo.reply_change_proposal_review_comment"
  @read_change_proposal_checks "repo.read_change_proposal_checks"
  @merge_change_proposal "repo.merge_change_proposal"
  @close_change_proposal "repo.close_change_proposal"

  @change_proposal_create "repo_provider.change_proposal.create"
  @change_proposal_read "repo_provider.change_proposal.read"
  @review_read "repo_provider.review.read"
  @review_write "repo_provider.review.write"
  @check_read "repo_provider.check.read"
  @merge "repo_provider.merge"

  @adapter_capability_map %{
    pr_create: @change_proposal_create,
    pr_view: @change_proposal_read,
    pr_reviews: @review_read,
    pr_checks: @check_read,
    pr_merge: @merge
  }

  @spec change_proposal_snapshot() :: String.t()
  def change_proposal_snapshot, do: @change_proposal_snapshot

  @spec create_or_update_change_proposal() :: String.t()
  def create_or_update_change_proposal, do: @create_or_update_change_proposal

  @spec read_change_proposal_discussion() :: String.t()
  def read_change_proposal_discussion, do: @read_change_proposal_discussion

  @spec add_change_proposal_comment() :: String.t()
  def add_change_proposal_comment, do: @add_change_proposal_comment

  @spec submit_change_proposal_review() :: String.t()
  def submit_change_proposal_review, do: @submit_change_proposal_review

  @spec reply_change_proposal_review_comment() :: String.t()
  def reply_change_proposal_review_comment, do: @reply_change_proposal_review_comment

  @spec read_change_proposal_checks() :: String.t()
  def read_change_proposal_checks, do: @read_change_proposal_checks

  @spec merge_change_proposal() :: String.t()
  def merge_change_proposal, do: @merge_change_proposal

  @spec close_change_proposal() :: String.t()
  def close_change_proposal, do: @close_change_proposal

  @spec change_proposal_create() :: String.t()
  def change_proposal_create, do: @change_proposal_create

  @spec change_proposal_read() :: String.t()
  def change_proposal_read, do: @change_proposal_read

  @spec review_read() :: String.t()
  def review_read, do: @review_read

  @spec review_write() :: String.t()
  def review_write, do: @review_write

  @spec check_read() :: String.t()
  def check_read, do: @check_read

  @spec merge() :: String.t()
  def merge, do: @merge

  @impl true
  def capabilities do
    typed_tool_capabilities() ++
      [
        change_proposal_create(),
        change_proposal_read(),
        review_read(),
        review_write(),
        check_read(),
        merge()
      ]
  end

  @impl true
  def typed_tool_capabilities do
    [
      change_proposal_snapshot(),
      create_or_update_change_proposal(),
      read_change_proposal_discussion(),
      add_change_proposal_comment(),
      submit_change_proposal_review(),
      reply_change_proposal_review_comment(),
      read_change_proposal_checks(),
      merge_change_proposal(),
      close_change_proposal()
    ]
  end

  @impl true
  def merge_gate_capabilities do
    [
      merge(),
      merge_change_proposal()
    ]
  end

  @impl true
  def known_provider_unavailable_capabilities, do: [submit_change_proposal_review()]

  @spec logical_capabilities(Enumerable.t()) :: [String.t()]
  def logical_capabilities(adapter_capabilities) do
    adapter_capabilities
    |> List.wrap()
    |> Enum.flat_map(&logical_capability/1)
  end

  @spec logical_capability(atom()) :: [String.t()]
  def logical_capability(adapter_capability) when is_atom(adapter_capability) do
    case Map.fetch(@adapter_capability_map, adapter_capability) do
      {:ok, capability} -> [capability]
      :error -> []
    end
  end

  def logical_capability(_adapter_capability), do: []
end
