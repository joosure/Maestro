defmodule SymphonyElixir.RepoProvider.LandWatch.RuntimeEnv do
  @moduledoc """
  Environment variable contract for repo-provider land-watch review controls.
  """

  @agent_review_bots_env "SYMPHONY_AGENT_REVIEW_BOTS"
  @review_request_token_env "SYMPHONY_AGENT_REVIEW_REQUEST_TOKEN"
  @reply_prefix_env "SYMPHONY_AGENT_REPLY_PREFIX"
  @review_heading_env "SYMPHONY_AGENT_REVIEW_HEADING"

  @default_agent_review_bots ""
  @default_review_request_token "@agent review"
  @default_reply_prefix "[agent]"
  @default_review_heading "## Agent Review"

  @spec agent_review_bots_env() :: String.t()
  def agent_review_bots_env, do: @agent_review_bots_env

  @spec review_request_token_env() :: String.t()
  def review_request_token_env, do: @review_request_token_env

  @spec reply_prefix_env() :: String.t()
  def reply_prefix_env, do: @reply_prefix_env

  @spec review_heading_env() :: String.t()
  def review_heading_env, do: @review_heading_env

  @spec default_agent_review_bots() :: String.t()
  def default_agent_review_bots, do: @default_agent_review_bots

  @spec default_review_request_token() :: String.t()
  def default_review_request_token, do: @default_review_request_token

  @spec default_reply_prefix() :: String.t()
  def default_reply_prefix, do: @default_reply_prefix

  @spec default_review_heading() :: String.t()
  def default_review_heading, do: @default_review_heading

  @spec agent_review_bots(map()) :: String.t()
  def agent_review_bots(env) when is_map(env),
    do: env_value(env, @agent_review_bots_env, @default_agent_review_bots)

  @spec review_request_token(map()) :: String.t()
  def review_request_token(env) when is_map(env),
    do: env_value(env, @review_request_token_env, @default_review_request_token)

  @spec reply_prefix(map()) :: String.t()
  def reply_prefix(env) when is_map(env),
    do: env_value(env, @reply_prefix_env, @default_reply_prefix)

  @spec review_heading(map()) :: String.t()
  def review_heading(env) when is_map(env),
    do: env_value(env, @review_heading_env, @default_review_heading)

  defp env_value(env, key, default) when is_map(env) and is_binary(key) do
    case Map.get(env, key, default) do
      value when is_binary(value) and value != "" -> value
      _value -> default
    end
  end
end
