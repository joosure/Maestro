defmodule SymphonyElixir.Tracker.Capabilities do
  @moduledoc """
  Tracker-owned capability strings.

  Workflow profiles may require these capabilities, but Tracker owns the
  vocabulary because it provides the issue, comment, relation, and tracker-tool
  surfaces.
  """

  @behaviour SymphonyElixir.Capability.Source

  @issue_read "tracker.issue.read"
  @issue_update "tracker.issue.update"
  @issue_create "tracker.issue.create"
  @comment_read "tracker.comment.read"
  @comment_write "tracker.comment.write"
  @comment_update "tracker.comment.update"
  @state_update "tracker.state.update"
  @relation_read "tracker.relation.read"
  @relation_write "tracker.relation.write"
  @issue_snapshot "tracker.issue_snapshot"
  @move_issue "tracker.move_issue"
  @upsert_workpad "tracker.upsert_workpad"
  @attach_external_reference "tracker.attach_external_reference"
  @upsert_comment "tracker.upsert_comment"
  @create_follow_up_issue "tracker.create_follow_up_issue"
  @read_issue_relations "tracker.read_issue_relations"
  @add_issue_relation "tracker.add_issue_relation"
  @read_issue_dependencies "tracker.read_issue_dependencies"
  @save_issue_dependency "tracker.save_issue_dependency"
  @prepare_file_upload "tracker.prepare_file_upload"
  @provider_diagnostics "tracker.provider_diagnostics"

  @spec issue_read() :: String.t()
  def issue_read, do: @issue_read

  @spec issue_update() :: String.t()
  def issue_update, do: @issue_update

  @spec issue_create() :: String.t()
  def issue_create, do: @issue_create

  @spec comment_read() :: String.t()
  def comment_read, do: @comment_read

  @spec comment_write() :: String.t()
  def comment_write, do: @comment_write

  @spec comment_update() :: String.t()
  def comment_update, do: @comment_update

  @spec state_update() :: String.t()
  def state_update, do: @state_update

  @spec relation_read() :: String.t()
  def relation_read, do: @relation_read

  @spec relation_write() :: String.t()
  def relation_write, do: @relation_write

  @spec issue_snapshot() :: String.t()
  def issue_snapshot, do: @issue_snapshot

  @spec move_issue() :: String.t()
  def move_issue, do: @move_issue

  @spec upsert_workpad() :: String.t()
  def upsert_workpad, do: @upsert_workpad

  @spec attach_external_reference() :: String.t()
  def attach_external_reference, do: @attach_external_reference

  @spec upsert_comment() :: String.t()
  def upsert_comment, do: @upsert_comment

  @spec create_follow_up_issue() :: String.t()
  def create_follow_up_issue, do: @create_follow_up_issue

  @spec read_issue_relations() :: String.t()
  def read_issue_relations, do: @read_issue_relations

  @spec add_issue_relation() :: String.t()
  def add_issue_relation, do: @add_issue_relation

  @spec read_issue_dependencies() :: String.t()
  def read_issue_dependencies, do: @read_issue_dependencies

  @spec save_issue_dependency() :: String.t()
  def save_issue_dependency, do: @save_issue_dependency

  @spec prepare_file_upload() :: String.t()
  def prepare_file_upload, do: @prepare_file_upload

  @spec provider_diagnostics() :: String.t()
  def provider_diagnostics, do: @provider_diagnostics

  @impl true
  def capabilities do
    [
      issue_read(),
      issue_update(),
      issue_create(),
      comment_read(),
      comment_write(),
      comment_update(),
      state_update(),
      relation_read(),
      relation_write(),
      issue_snapshot(),
      move_issue(),
      upsert_workpad(),
      attach_external_reference(),
      upsert_comment(),
      create_follow_up_issue(),
      read_issue_relations(),
      add_issue_relation(),
      read_issue_dependencies(),
      save_issue_dependency(),
      prepare_file_upload(),
      provider_diagnostics()
    ]
  end

  @impl true
  def typed_tool_capabilities do
    [
      issue_snapshot(),
      move_issue(),
      upsert_workpad(),
      attach_external_reference(),
      upsert_comment(),
      create_follow_up_issue(),
      read_issue_relations(),
      add_issue_relation(),
      read_issue_dependencies(),
      save_issue_dependency(),
      prepare_file_upload(),
      provider_diagnostics()
    ]
  end

  @impl true
  def diagnostic_capabilities, do: [provider_diagnostics()]
end
