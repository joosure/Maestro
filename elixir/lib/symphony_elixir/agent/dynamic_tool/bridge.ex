defmodule SymphonyElixir.Agent.DynamicTool.Bridge do
  @moduledoc """
  Provider-neutral bridge for external agent provider processes to execute
  agent dynamic tools.
  """

  alias SymphonyElixir.Agent.DynamicTool.{
    Context,
    EventContract,
    ExecutionGuard,
    Policy,
    Source,
    Spec,
    TypedToolFailurePolicy
  }

  alias SymphonyElixir.Agent.DynamicTool.Bridge.{Audit, Registry, Request, Result}
  alias SymphonyElixir.Agent.DynamicTool.ExecutionGuard.Decision, as: GuardDecision
  alias SymphonyElixir.Agent.DynamicTool.ExecutionGuard.ErrorPayload, as: GuardErrorPayload
  alias SymphonyElixir.Agent.DynamicTool.Policy.Decision, as: PolicyDecision
  alias SymphonyElixir.Agent.DynamicTool.Policy.Error, as: PolicyError
  alias SymphonyElixir.Agent.DynamicTool.Policy.ErrorPayload, as: PolicyErrorPayload
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.Platform.DynamicToolBridgeContract, as: BridgeContract
  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response

  @token_key {__MODULE__, :token}
  @type bridge_result :: %{
          required(String.t()) => boolean() | map()
        }

  @spec token() :: String.t()
  def token do
    configured_token() || generated_token()
  end

  @spec register_context(Context.t() | map()) :: String.t()
  defdelegate register_context(tool_context), to: Registry, as: :register

  @spec unregister_context(term()) :: :ok
  defdelegate unregister_context(token), to: Registry, as: :unregister

  @spec valid_token?(term()) :: boolean()
  def valid_token?(candidate) when is_binary(candidate) do
    Registry.registered?(candidate) or Plug.Crypto.secure_compare(candidate, token())
  rescue
    _error -> false
  end

  def valid_token?(_candidate), do: false

  @spec put_token_context(keyword(), String.t()) :: keyword()
  def put_token_context(opts, token) when is_list(opts) and is_binary(token) do
    case Registry.fetch(token) do
      {:ok, tool_context} -> Keyword.put(opts, :tool_context, tool_context)
      :error -> opts
    end
  end

  def put_token_context(opts, _token) when is_list(opts), do: opts

  @spec execute(String.t() | nil, term(), keyword()) :: bridge_result()
  def execute(tool, arguments, opts \\ []) do
    request = Request.new(tool, arguments, opts)
    request = Request.put_audit_fields(request, Audit.request_fields(request))

    ObservabilityLogger.emit(:info, EventContract.tool_call_requested_event(), request.audit_fields)

    case supported_tool_spec(request) do
      %{} ->
        execute_supported_tool(request)

      _tool_spec ->
        reject_tool_call(
          Response.error_payload(
            EventContract.unsupported_tool(),
            "Unsupported dynamic tool: #{inspect(tool)}.",
            %{Response.supported_tools_key() => supported_tool_names(request.tool_context)}
          ),
          request
        )
    end
  end

  defp execute_supported_tool(%Request{} = request) do
    with :ok <- ExecutionGuard.ensure_authoritative_typed_tool(request.tool_context, request.canonical_tool),
         {:ok, policy_config} <- Request.policy_config(request),
         :ok <- Policy.authorize(request.tool_context, request.canonical_tool, policy_config) do
      ObservabilityLogger.emit(:info, EventContract.tool_call_started_event(), request.audit_fields)

      result =
        request.source
        |> Source.execute_canonical(
          request.source_context,
          request.provider_tool,
          request.canonical_tool,
          request.arguments,
          Request.source_opts(request)
        )
        |> TypedToolFailurePolicy.apply(
          request.tool_context,
          request.canonical_tool,
          request.arguments,
          Request.failure_policy_opts(request)
        )
        |> Result.normalize()

      {level, event} =
        if Response.success?(result),
          do: {:info, EventContract.tool_call_succeeded_event()},
          else: {:warning, EventContract.tool_call_failed_event()}

      ObservabilityLogger.emit(
        level,
        event,
        Map.merge(request.audit_fields, Audit.result_fields(result, request.started_at_ms, request.opts))
      )

      result
    else
      {:error, %GuardDecision{} = decision} ->
        decision
        |> GuardErrorPayload.from_decision()
        |> reject_tool_call(request)

      {:error, %PolicyDecision{} = decision} ->
        decision
        |> PolicyErrorPayload.from_decision()
        |> reject_tool_call(request)

      {:error, %PolicyError{} = error} ->
        error
        |> PolicyErrorPayload.from_error()
        |> reject_tool_call(request)
    end
  end

  defp reject_tool_call(payload, %Request{} = request) do
    response = Result.failure(payload)

    ObservabilityLogger.emit(
      :warning,
      EventContract.tool_call_rejected_event(),
      Map.merge(request.audit_fields, Audit.rejection_fields(response, request.started_at_ms))
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

  defp supported_tool_names(tool_context) do
    name_key = Spec.name_key()

    tool_context
    |> Context.tool_specs()
    |> Enum.flat_map(&tool_spec_name(&1, name_key))
  end

  defp tool_spec_name(tool_spec, name_key) when is_map(tool_spec) and is_binary(name_key) do
    case Map.get(tool_spec, name_key) do
      name when is_binary(name) -> [name]
      _name -> []
    end
  end

  defp tool_spec_name(_tool_spec, _name_key), do: []

  defp supported_tool_spec(%Request{tool_context: tool_context, provider_tool: tool}) when is_binary(tool) do
    Context.tool_spec(tool_context, tool)
  end

  defp supported_tool_spec(%Request{}), do: nil
end
