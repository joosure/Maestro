defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Evidence do
  @moduledoc """
  Stable observation bucket and field keys used by readiness policies.
  """

  @status_key "status"
  @source_key "source"
  @key_key "key"
  @id_key "id"
  @url_key "url"
  @observed_at_key "observed_at"
  @updated_at_key "updated_at"
  @summary_key "summary"

  @spec status_key() :: String.t()
  def status_key, do: @status_key

  @spec source_key() :: String.t()
  def source_key, do: @source_key

  @spec key_key() :: String.t()
  def key_key, do: @key_key

  @spec id_key() :: String.t()
  def id_key, do: @id_key

  @spec url_key() :: String.t()
  def url_key, do: @url_key

  @spec observed_at_key() :: String.t()
  def observed_at_key, do: @observed_at_key

  @spec updated_at_key() :: String.t()
  def updated_at_key, do: @updated_at_key

  @spec summary_key() :: String.t()
  def summary_key, do: @summary_key
end
