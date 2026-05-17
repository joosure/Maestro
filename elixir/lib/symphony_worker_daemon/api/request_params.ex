defmodule SymphonyWorkerDaemon.Api.RequestParams do
  @moduledoc false

  alias SymphonyWorkerDaemon.Protocol.Fields

  @default_max_request_body_bytes 1_048_576

  @spec body_params(Plug.Conn.t()) :: map()
  def body_params(%Plug.Conn{body_params: %Plug.Conn.Unfetched{}}), do: %{}
  def body_params(%Plug.Conn{body_params: params}) when is_map(params), do: params
  def body_params(_conn), do: %{}

  @spec session_filters(map()) :: map()
  def session_filters(query_params) when is_map(query_params) do
    Map.take(query_params, Fields.session_filter_keys())
  end

  @spec event_filters(map()) :: keyword()
  def event_filters(query_params) when is_map(query_params) do
    [
      after_event_id: Map.get(query_params, Fields.after_event_id()),
      limit: Map.get(query_params, Fields.limit())
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  @spec protocol_limit_opts(keyword()) :: keyword()
  def protocol_limit_opts(opts) when is_list(opts) do
    [
      max_protocol_request_bytes: Keyword.get(opts, :max_protocol_request_bytes, @default_max_request_body_bytes),
      max_protocol_caller_bytes: Keyword.get(opts, :max_protocol_caller_bytes),
      max_protocol_command_bytes: Keyword.get(opts, :max_protocol_command_bytes),
      max_protocol_env_bytes: Keyword.get(opts, :max_protocol_env_bytes),
      max_protocol_dynamic_tool_bridge_bytes: Keyword.get(opts, :max_protocol_dynamic_tool_bridge_bytes),
      max_protocol_input_bytes: Keyword.get(opts, :max_protocol_input_bytes, @default_max_request_body_bytes)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end
end
