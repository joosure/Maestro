defmodule SymphonyElixir.Agent.DynamicTool.Bridge do
  @moduledoc """
  Provider-neutral bridge for external agent provider processes to execute
  agent dynamic tools.
  """

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.DynamicTool.BridgeContract
  alias SymphonyElixir.Agent.DynamicTool.BridgeRegistry
  alias SymphonyElixir.Agent.DynamicTool.{Context, EventContract, Policy, Serializer, TypedToolFailurePolicy, Usage}
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.Observability.Redaction
  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response

  @token_key {__MODULE__, :token}
  @dialyzer {:nowarn_function, normalize_dynamic_tool_result: 1}

  @type bridge_result :: %{
          required(String.t()) => boolean() | map()
        }

  @spec token() :: String.t()
  def token do
    configured_token() || generated_token()
  end

  @spec register_context(map()) :: String.t()
  defdelegate register_context(tool_context), to: BridgeRegistry, as: :register

  @spec unregister_context(term()) :: :ok
  defdelegate unregister_context(token), to: BridgeRegistry, as: :unregister

  @spec valid_token?(term()) :: boolean()
  def valid_token?(candidate) when is_binary(candidate) do
    BridgeRegistry.registered?(candidate) or Plug.Crypto.secure_compare(candidate, token())
  rescue
    _error -> false
  end

  def valid_token?(_candidate), do: false

  @spec put_token_context(keyword(), String.t()) :: keyword()
  def put_token_context(opts, token) when is_list(opts) and is_binary(token) do
    case BridgeRegistry.fetch(token) do
      {:ok, tool_context} -> Keyword.put(opts, :tool_context, tool_context)
      :error -> opts
    end
  end

  def put_token_context(opts, _token) when is_list(opts), do: opts

  @spec execute(String.t() | nil, term(), keyword()) :: bridge_result()
  def execute(tool, arguments, opts \\ []) do
    tool_context = Context.from_opts(opts)
    started_at_ms = System.monotonic_time(:millisecond)
    base_fields = audit_fields(tool_context, tool, arguments, opts)

    ObservabilityLogger.emit(:info, EventContract.tool_call_requested_event(), base_fields)

    case supported_tool_spec(tool_context, tool) do
      %{} ->
        execute_supported_tool(tool_context, tool, arguments, opts, base_fields, started_at_ms)

      _tool_spec ->
        reject_tool_call(
          Response.error_payload(
            EventContract.unsupported_tool(),
            "Unsupported dynamic tool: #{inspect(tool)}.",
            %{EventContract.supported_tools_key() => supported_tool_names(tool_context)}
          ),
          base_fields,
          started_at_ms
        )
    end
  end

  defp execute_supported_tool(tool_context, tool, arguments, opts, base_fields, started_at_ms) do
    case Policy.authorize(tool_context, tool, opts) do
      :ok ->
        ObservabilityLogger.emit(:info, EventContract.tool_call_started_event(), base_fields)

        result =
          tool_context
          |> DynamicTool.execute(tool, arguments, opts)
          |> TypedToolFailurePolicy.apply(tool_context, tool, arguments, opts)
          |> normalize_dynamic_tool_result()

        {level, event} =
          if Response.success?(result),
            do: {:info, EventContract.tool_call_succeeded_event()},
            else: {:warning, EventContract.tool_call_failed_event()}

        ObservabilityLogger.emit(
          level,
          event,
          Map.merge(base_fields, %{
            duration_ms: elapsed_ms(started_at_ms),
            dynamic_tool_failure_reason: Usage.failure_reason(result),
            dynamic_tool_provider_capability_unavailable_count: Usage.provider_capability_unavailable_count(result),
            dynamic_tool_provider_capability_unavailable: Usage.provider_capability_unavailable_details(result),
            result_summary: Redaction.summarize(result)
          })
        )

        result

      {:error, payload} ->
        reject_tool_call(payload, base_fields, started_at_ms)
    end
  end

  defp reject_tool_call(payload, base_fields, started_at_ms) do
    response = failure_response(payload)

    ObservabilityLogger.emit(
      :warning,
      EventContract.tool_call_rejected_event(),
      Map.merge(base_fields, %{
        duration_ms: elapsed_ms(started_at_ms),
        dynamic_tool_failure_reason: Usage.failure_reason(response),
        dynamic_tool_provider_capability_unavailable_count: Usage.provider_capability_unavailable_count(response),
        dynamic_tool_provider_capability_unavailable: Usage.provider_capability_unavailable_details(response),
        dynamic_tool_rejection_reason: Usage.failure_reason(response),
        result_summary: Redaction.summarize(response)
      })
    )

    response
  end

  defp configured_token do
    case Application.get_env(:symphony_elixir, BridgeContract.token_config_key()) ||
           System.get_env(BridgeContract.token_env()) do
      token when is_binary(token) and token != "" -> token
      _token -> nil
    end
  end

  defp generated_token do
    case :persistent_term.get(@token_key, nil) do
      token when is_binary(token) ->
        token

      _token ->
        token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
        :persistent_term.put(@token_key, token)
        token
    end
  end

  @spec normalize_dynamic_tool_result(term()) :: bridge_result()
  defp normalize_dynamic_tool_result({:success, payload}) do
    Response.success(Serializer.json_safe_value(payload))
  end

  defp normalize_dynamic_tool_result({:failure, payload}) do
    failure_response(payload)
  end

  defp normalize_dynamic_tool_result({:error, %{__struct__: _struct} = error}) do
    failure_response(%{Response.error_key() => Serializer.error_payload(error)})
  end

  defp normalize_dynamic_tool_result({:error, reason}) do
    failure_response(Response.error_payload(nil, "Dynamic tool execution failed.", %{"reason" => inspect(reason)}))
  end

  defp normalize_dynamic_tool_result(result) do
    failure_response(Response.error_payload(nil, "Dynamic tool execution returned an invalid result.", %{"result" => inspect(result)}))
  end

  defp failure_response(payload) do
    Response.failure(Serializer.json_safe_value(payload))
  end

  defp audit_fields(tool_context, tool, arguments, opts) do
    runtime_metadata = Map.get(tool_context, :runtime_metadata, %{})

    %{
      component: "agent.dynamic_tool_bridge",
      tool_name: tool,
      run_id: audit_value(opts, runtime_metadata, :run_id),
      correlation_id: audit_value(opts, runtime_metadata, :run_id),
      issue_id: audit_value(opts, runtime_metadata, :issue_id),
      issue_identifier: audit_value(opts, runtime_metadata, :issue_identifier),
      dynamic_tool_source_kind: Context.source_kind(tool_context),
      agent_provider_kind: audit_value(opts, runtime_metadata, :agent_provider_kind),
      session_id: audit_value(opts, runtime_metadata, :session_id),
      thread_id: audit_value(opts, runtime_metadata, :thread_id),
      turn_id: audit_value(opts, runtime_metadata, :turn_id),
      worker_host: audit_value(opts, runtime_metadata, :worker_host),
      workspace_path: Keyword.get(opts, :workspace),
      payload_summary: Redaction.summarize(arguments)
    }
    |> Map.merge(Usage.audit_fields(tool_context, tool, opts))
  end

  defp audit_value(opts, runtime_metadata, key) when is_list(opts) and is_map(runtime_metadata) do
    Keyword.get(opts, key) || Map.get(runtime_metadata, key) || Map.get(runtime_metadata, Atom.to_string(key))
  end

  defp elapsed_ms(started_at_ms) when is_integer(started_at_ms) do
    max(System.monotonic_time(:millisecond) - started_at_ms, 0)
  end

  defp supported_tool_names(tool_context) do
    tool_context
    |> Context.tool_specs()
    |> Enum.flat_map(fn
      %{"name" => name} when is_binary(name) -> [name]
      %{name: name} when is_binary(name) -> [name]
      _tool -> []
    end)
  end

  defp supported_tool_spec(tool_context, tool) when is_binary(tool) do
    Context.tool_spec(tool_context, tool)
  end

  defp supported_tool_spec(_tool_context, _tool), do: nil
end
