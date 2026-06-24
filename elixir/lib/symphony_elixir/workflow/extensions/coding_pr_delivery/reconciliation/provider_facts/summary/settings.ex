defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Summary.Settings do
  @moduledoc false

  @agent_review_bots_env "SYMPHONY_AGENT_REVIEW_BOTS"
  @review_request_token_env "SYMPHONY_AGENT_REVIEW_REQUEST_TOKEN"
  @reply_prefix_env "SYMPHONY_AGENT_REPLY_PREFIX"
  @review_heading_env "SYMPHONY_AGENT_REVIEW_HEADING"

  @default_agent_review_bots ""
  @default_review_request_token "@agent review"
  @default_reply_prefix "[agent]"
  @default_review_heading "## Agent Review"

  @type t :: %__MODULE__{
          agent_review_bots: MapSet.t(String.t()),
          request_token: String.t(),
          reply_prefix: String.t(),
          review_heading: String.t()
        }

  defstruct agent_review_bots: MapSet.new(),
            request_token: @default_review_request_token,
            reply_prefix: @default_reply_prefix,
            review_heading: @default_review_heading

  @spec from_env(map() | list()) :: t()
  def from_env(env) when is_list(env), do: env |> Map.new() |> from_env()

  def from_env(env) when is_map(env) do
    %__MODULE__{
      agent_review_bots:
        env
        |> env_value(@agent_review_bots_env, @default_agent_review_bots)
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> MapSet.new(),
      request_token: env_value(env, @review_request_token_env, @default_review_request_token),
      reply_prefix: env_value(env, @reply_prefix_env, @default_reply_prefix),
      review_heading: env_value(env, @review_heading_env, @default_review_heading)
    }
  end

  defp env_value(env, key, default) when is_map(env) and is_binary(key) do
    case Map.get(env, key, default) do
      value when is_binary(value) and value != "" -> value
      _value -> default
    end
  end
end
