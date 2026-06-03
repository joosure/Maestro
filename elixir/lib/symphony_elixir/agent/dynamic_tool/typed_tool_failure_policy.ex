defmodule SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy do
  @moduledoc """
  Classifies repeated structured failures at the typed-tool execution boundary.

  Provider adapters report domain failures once. This policy owns cross-provider
  retry classification so adapters do not duplicate throttling logic.
  """

  use GenServer

  alias SymphonyElixir.Agent.DynamicTool.{EventContract, Serializer}
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger

  @default_threshold 3
  @review_handoff_not_ready_code "review_handoff_not_ready"
  @review_handoff_blocked_code "review_handoff_blocked_after_retries"
  @remediation_actions_key "remediation_actions"
  @missing_evidence_key "missing_evidence"

  @retry_policies %{
    @review_handoff_not_ready_code => %{
      blocked_code: @review_handoff_blocked_code,
      message: "Review handoff remains blocked after repeated structured readiness failures."
    }
  }

  @type result :: {:success, term()} | {:failure, term()} | term()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       counts: %{},
       threshold: Keyword.get(opts, :threshold, configured_threshold())
     }}
  end

  @spec apply(result(), map(), String.t() | nil, term(), keyword()) :: result()
  def apply({:failure, payload}, tool_context, tool, arguments, opts) do
    case error_code(payload) do
      code when is_map_key(@retry_policies, code) ->
        record_failure(payload, tool_context, tool, arguments, opts, code, Map.fetch!(@retry_policies, code))

      _code ->
        {:failure, payload}
    end
  end

  def apply({:success, _payload} = result, tool_context, tool, arguments, opts) do
    reset_tool_scope(tool_context, tool, arguments, opts)
    result
  end

  def apply(result, _tool_context, _tool, _arguments, _opts), do: result

  @spec reset() :: :ok
  def reset do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :reset)
    else
      :ok
    end
  end

  @impl true
  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | counts: %{}}}
  end

  def handle_call({:record_failure, key}, _from, state) do
    count = Map.get(state.counts, key, 0) + 1
    {:reply, {count, state.threshold}, %{state | counts: Map.put(state.counts, key, count)}}
  end

  def handle_call({:reset_tool_scope, scope}, _from, state) do
    counts =
      Map.reject(state.counts, fn
        {{run_id, resource_kind, resource_id, tool, _code}, _count} ->
          {run_id, resource_kind, resource_id, tool} == scope

        _entry ->
          false
      end)

    {:reply, :ok, %{state | counts: counts}}
  end

  defp record_failure(payload, tool_context, tool, arguments, opts, code, policy) do
    case failure_key(tool_context, tool, arguments, opts, code) do
      {:ok, key} ->
        {count, threshold} = record_failure_count(key)

        if count >= threshold do
          blocked = blocked_payload(payload, key, count, threshold, policy)
          emit_blocked(tool_context, key, count, threshold, policy, opts)
          {:failure, blocked}
        else
          {:failure, payload}
        end

      :unscoped ->
        emit_skipped_unscoped(tool_context, tool, arguments, opts, code)
        {:failure, payload}
    end
  end

  defp record_failure_count(key) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:record_failure, key})
    else
      {1, configured_threshold()}
    end
  end

  defp reset_tool_scope(tool_context, tool, arguments, opts) do
    if Process.whereis(__MODULE__) do
      case failure_key(tool_context, tool, arguments, opts, @review_handoff_not_ready_code) do
        {:ok, {run_id, resource_kind, resource_id, tool_name, _code}} ->
          GenServer.call(__MODULE__, {:reset_tool_scope, {run_id, resource_kind, resource_id, tool_name}})

        :unscoped ->
          :ok
      end
    end

    :ok
  end

  defp blocked_payload(payload, {run_id, resource_kind, resource_id, tool, original_code}, count, threshold, policy) do
    original_details = error_details(payload)

    %{
      "error" => %{
        "code" => Map.fetch!(policy, :blocked_code),
        "message" => Map.fetch!(policy, :message),
        "retryable" => false,
        "details" => %{
          "original_code" => original_code,
          "retryable" => false,
          "failure_count" => count,
          "failure_threshold" => threshold,
          "run_id" => run_id,
          "resource" => %{
            "kind" => resource_kind,
            "id" => resource_id
          },
          "tool" => tool,
          @missing_evidence_key => detail_list(original_details, @missing_evidence_key),
          @remediation_actions_key => detail_list(original_details, @remediation_actions_key),
          "original_details" => original_details
        }
      }
    }
    |> Serializer.json_safe_value()
  end

  defp failure_key(tool_context, tool, arguments, opts, code) do
    runtime_metadata = Map.get(tool_context || %{}, :runtime_metadata, %{})

    case resource_identity(runtime_metadata, arguments) do
      %{kind: resource_kind, id: resource_id} ->
        {:ok,
         {
           scoped_value(opts, runtime_metadata, :run_id) ||
             scoped_value(opts, runtime_metadata, :session_id) ||
             scoped_value(opts, runtime_metadata, :turn_id) ||
             "unknown_run",
           resource_kind,
           resource_id,
           if(is_binary(tool), do: tool, else: inspect(tool)),
           code
         }}

      nil ->
        :unscoped
    end
  end

  defp resource_identity(runtime_metadata, arguments) do
    cond do
      value = scoped_value([], runtime_metadata, :resource_id) ->
        %{kind: scoped_value([], runtime_metadata, :resource_kind) || "resource", id: value}

      value = scoped_value([], runtime_metadata, :issue_id) || argument_value(arguments, "issue_id") || argument_value(arguments, :issue_id) ->
        %{kind: "tracker_issue", id: value}

      value = argument_value(arguments, "change_proposal_id") || argument_value(arguments, :change_proposal_id) ->
        %{kind: "change_proposal", id: value}

      value = argument_value(arguments, "pr_url") || argument_value(arguments, :pr_url) ->
        %{kind: "change_proposal", id: value}

      value = argument_value(arguments, "pull_request_url") || argument_value(arguments, :pull_request_url) ->
        %{kind: "change_proposal", id: value}

      value = argument_value(arguments, "branch") || argument_value(arguments, :branch) ->
        %{kind: "repo_branch", id: value}

      value = scoped_value([], runtime_metadata, :session_id) ->
        %{kind: "agent_session", id: value}

      true ->
        nil
    end
  end

  defp emit_skipped_unscoped(tool_context, tool, arguments, opts, code) do
    runtime_metadata = Map.get(tool_context || %{}, :runtime_metadata, %{})

    ObservabilityLogger.emit(:debug, EventContract.typed_tool_failure_policy_skipped_unscoped_event(), %{
      component: "agent.dynamic_tool_failure_policy",
      reason: "missing_resource_identity",
      error_code: code,
      tool_name: if(is_binary(tool), do: tool, else: inspect(tool)),
      run_id:
        scoped_value(opts, runtime_metadata, :run_id) ||
          scoped_value(opts, runtime_metadata, :session_id) ||
          scoped_value(opts, runtime_metadata, :turn_id),
      session_id: scoped_value(opts, runtime_metadata, :session_id),
      turn_id: scoped_value(opts, runtime_metadata, :turn_id),
      payload_summary: inspect(argument_keys(arguments))
    })

    :ok
  end

  defp emit_blocked(tool_context, {run_id, resource_kind, resource_id, tool, original_code}, count, threshold, policy, opts) do
    runtime_metadata = Map.get(tool_context || %{}, :runtime_metadata, %{})
    blocked_code = Map.fetch!(policy, :blocked_code)

    fields =
      %{
        component: "agent.dynamic_tool_failure_policy",
        run_id: run_id,
        session_id: scoped_value(opts, runtime_metadata, :session_id),
        turn_id: scoped_value(opts, runtime_metadata, :turn_id),
        tool_name: tool,
        error_code: blocked_code,
        original_error_code: original_code,
        retryable: false,
        failure_count: count,
        failure_threshold: threshold,
        resource_kind: resource_kind,
        resource_id: resource_id,
        result_summary: "typed_tool_non_retryable_blocker"
      }
      |> maybe_put_tracker_issue(resource_kind, resource_id)

    ObservabilityLogger.emit(:warning, EventContract.typed_tool_failure_policy_blocked_event(), fields)

    :ok
  end

  defp maybe_put_tracker_issue(fields, "tracker_issue", issue_id), do: Map.put(fields, :issue_id, issue_id)
  defp maybe_put_tracker_issue(fields, _resource_kind, _resource_id), do: fields

  defp argument_keys(arguments) when is_map(arguments) do
    arguments
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.sort()
  end

  defp argument_keys(_arguments), do: []

  defp scoped_value(opts, runtime_metadata, key) do
    Keyword.get(opts, key) || Map.get(runtime_metadata, key) || Map.get(runtime_metadata, Atom.to_string(key))
  end

  defp argument_value(arguments, key) when is_map(arguments), do: Map.get(arguments, key)
  defp argument_value(_arguments, _key), do: nil

  defp error_code(payload), do: get_in(payload, ["error", "code"]) || get_in(payload, [:error, :code])

  defp error_details(payload) do
    get_in(payload, ["error", "details"]) || get_in(payload, [:error, :details]) || %{}
  end

  defp detail_list(details, @missing_evidence_key) when is_map(details) do
    normalize_detail_list(Map.get(details, @missing_evidence_key) || Map.get(details, :missing_evidence))
  end

  defp detail_list(details, @remediation_actions_key) when is_map(details) do
    normalize_detail_list(Map.get(details, @remediation_actions_key) || Map.get(details, :remediation_actions))
  end

  defp detail_list(details, key) when is_map(details) do
    normalize_detail_list(Map.get(details, key))
  end

  defp detail_list(_details, _key), do: []

  defp normalize_detail_list(values) when is_list(values), do: values
  defp normalize_detail_list(nil), do: []
  defp normalize_detail_list(value), do: [value]

  defp configured_threshold do
    case Application.get_env(:symphony_elixir, :typed_tool_failure_retry_threshold, @default_threshold) do
      threshold when is_integer(threshold) and threshold > 0 -> threshold
      _threshold -> @default_threshold
    end
  end
end
