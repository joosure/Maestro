defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceStore do
  @moduledoc """
  Coding PR Delivery readiness evidence-store port.

  Review-handoff policies and recorders depend on this extension-owned port
  instead of the platform readiness store module. Bundled deployments adapt the
  platform store through
  `HostAdapters.Readiness.StateTransitionReadinessBackend`; an external plugin
  package can provide another backend without changing policy code.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Readiness.EventEmitterDefaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Readiness.StateTransitionReadinessBackend
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Envelope

  @callback snapshot(term(), keyword()) :: map()
  @callback record(term() | [term()], map(), keyword()) :: :ok
  @callback scope_issue_keys(term(), term() | [term()], keyword()) :: [String.t()]

  @default_backend StateTransitionReadinessBackend
  @backend_opt :readiness_evidence_store_backend
  @backend_opts_key :readiness_evidence_store_opts
  @component "workflow.extensions.coding_pr_delivery.readiness.evidence_store"
  @emit_event_fn_key :emit_event_fn
  @error_code "coding_pr_delivery_readiness_evidence_store_error"
  @error_event :coding_pr_delivery_readiness_evidence_store_error
  @observations_key Envelope.observations_key()
  @declarations_key Envelope.declarations_key()
  @metadata_key Envelope.metadata_key()
  @operation_record "record"
  @operation_scope_issue_keys "scope_issue_keys"
  @operation_snapshot "snapshot"

  @spec snapshot(term(), keyword()) :: map()
  def snapshot(keys, opts \\ []) do
    with {:ok, opts} <- normalize_opts(opts),
         {:ok, backend} <- backend(opts),
         snapshot when is_map(snapshot) <- call_snapshot(backend, keys, backend_opts(opts)) do
      snapshot
    else
      {:error, reason} ->
        emit_error(opts, @operation_snapshot, reason)
        empty_evidence()
    end
  end

  @spec record(term() | [term()], map(), keyword()) :: :ok
  def record(keys, evidence, opts \\ [])

  def record(keys, evidence, opts) when is_map(evidence) do
    with {:ok, opts} <- normalize_opts(opts),
         {:ok, backend} <- backend(opts),
         :ok <- call_record(backend, keys, evidence, backend_opts(opts)) do
      :ok
    else
      {:error, reason} ->
        emit_error(opts, @operation_record, reason)
        :ok
    end
  end

  def record(_keys, _evidence, opts) do
    emit_error(opts, @operation_record, %{reason: :invalid_evidence, value_type: "term"})
    :ok
  end

  @spec scope_issue_keys(term(), term() | [term()], keyword()) :: [String.t()]
  def scope_issue_keys(run_id, issue_keys, opts \\ []) do
    with {:ok, opts} <- normalize_opts(opts),
         {:ok, backend} <- backend(opts),
         scoped_keys when is_list(scoped_keys) <- call_scope_issue_keys(backend, run_id, issue_keys, backend_opts(opts)) do
      scoped_keys
    else
      {:error, reason} ->
        emit_error(opts, @operation_scope_issue_keys, reason)
        []

      value ->
        emit_error(opts, @operation_scope_issue_keys, invalid_backend_return(value))
        []
    end
  end

  defp normalize_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, opts}
    else
      {:error, %{reason: :opts_not_keyword, value_type: "non_keyword_list"}}
    end
  end

  defp normalize_opts(opts), do: {:error, %{reason: :opts_not_keyword, value_type: Diagnostics.type_name(opts)}}

  defp backend(opts) do
    backend = Keyword.get(opts, @backend_opt, @default_backend)

    cond do
      not is_atom(backend) ->
        {:error, %{reason: :invalid_backend, backend_type: Diagnostics.type_name(backend)}}

      not Code.ensure_loaded?(backend) ->
        {:error, %{reason: :invalid_backend, backend_type: "module_not_loaded"}}

      not backend_callbacks?(backend) ->
        {:error, %{reason: :invalid_backend, backend_type: "missing_callbacks"}}

      true ->
        {:ok, backend}
    end
  end

  defp backend_callbacks?(backend) do
    function_exported?(backend, :snapshot, 2) and
      function_exported?(backend, :record, 3) and
      function_exported?(backend, :scope_issue_keys, 3)
  end

  defp backend_opts(opts) do
    opts
    |> Keyword.get(@backend_opts_key, [])
    |> normalize_backend_opts()
  end

  defp normalize_backend_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: opts, else: []
  end

  defp normalize_backend_opts(_opts), do: []

  defp call_snapshot(backend, keys, opts) do
    case backend.snapshot(keys, opts) do
      snapshot when is_map(snapshot) -> snapshot
      value -> {:error, invalid_backend_return(value)}
    end
  rescue
    error -> {:error, backend_failure(error)}
  catch
    kind, reason -> {:error, backend_failure(kind, reason)}
  end

  defp call_record(backend, keys, evidence, opts) do
    case backend.record(keys, evidence, opts) do
      :ok -> :ok
      value -> {:error, invalid_backend_return(value)}
    end
  rescue
    error -> {:error, backend_failure(error)}
  catch
    kind, reason -> {:error, backend_failure(kind, reason)}
  end

  defp call_scope_issue_keys(backend, run_id, issue_keys, opts) do
    case backend.scope_issue_keys(run_id, issue_keys, opts) do
      scoped_keys when is_list(scoped_keys) -> scoped_keys
      value -> {:error, invalid_backend_return(value)}
    end
  rescue
    error -> {:error, backend_failure(error)}
  catch
    kind, reason -> {:error, backend_failure(kind, reason)}
  end

  defp backend_failure(%_{} = error), do: Map.put(Diagnostics.exception(error), :reason, :backend_failed)
  defp backend_failure(kind, reason), do: Map.put(Diagnostics.caught(kind, reason), :reason, :backend_failed)
  defp invalid_backend_return(value), do: %{reason: :invalid_backend_return, return_type: Diagnostics.type_name(value)}

  defp emit_error(opts, operation, reason) do
    emit_event_fn(opts).(:warning, @error_event, %{
      component: @component,
      error_code: @error_code,
      operation: operation,
      payload_summary: bounded_reason(reason)
    })

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp emit_event_fn(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      case Keyword.get(opts, @emit_event_fn_key) do
        emit_event_fn when is_function(emit_event_fn, 3) -> emit_event_fn
        _other -> &EventEmitterDefaults.emit/3
      end
    else
      &EventEmitterDefaults.emit/3
    end
  end

  defp emit_event_fn(_opts), do: &EventEmitterDefaults.emit/3

  defp bounded_reason(reason) when is_map(reason) do
    Map.take(reason, [:reason, :value_type, :backend_type, :return_type, :kind, :exception, :reason_type])
  end

  defp empty_evidence do
    %{
      @observations_key => %{},
      @declarations_key => %{},
      @metadata_key => %{}
    }
  end
end
