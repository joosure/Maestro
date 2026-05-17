defmodule SymphonyElixir.Tracker.Tapd.Client.Paths do
  @moduledoc """
  Provider-owned TAPD API path contract used by typed tracker tools.
  """

  @comments "/comments"
  @stories "/stories"
  @quickstart_testauth "/quickstart/testauth"
  @story_link_relations "/stories/get_link_stories"
  @story_time_relations "/stories/get_time_relative_stories"
  @add_story_link_relations "/stories/add_story_link_relations"
  @save_story_time_relations "/stories/save_time_relations"
  @workflow_last_steps "/workflows/last_steps"

  @spec comments() :: String.t()
  def comments, do: @comments

  @spec stories() :: String.t()
  def stories, do: @stories

  @spec quickstart_testauth() :: String.t()
  def quickstart_testauth, do: @quickstart_testauth

  @spec story_link_relations() :: String.t()
  def story_link_relations, do: @story_link_relations

  @spec story_time_relations() :: String.t()
  def story_time_relations, do: @story_time_relations

  @spec add_story_link_relations() :: String.t()
  def add_story_link_relations, do: @add_story_link_relations

  @spec save_story_time_relations() :: String.t()
  def save_story_time_relations, do: @save_story_time_relations

  @spec workflow_last_steps() :: String.t()
  def workflow_last_steps, do: @workflow_last_steps
end
