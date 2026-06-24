defmodule SymphonyElixir.Agent.Quota do
  @moduledoc false

  alias SymphonyElixir.Agent.Capabilities, as: AgentCapabilities
  alias SymphonyElixir.Agent.Credential.Store, as: CredentialStore
  alias SymphonyElixir.Agent.Quota.Snapshot
  alias SymphonyElixir.AgentProvider.{Config, Error}
  alias SymphonyElixir.Config, as: RuntimeConfig
  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Observability.OperationStatus
  alias SymphonyElixir.Observability.Redaction

  @probe_capability AgentCapabilities.quota_probe()

  @spec preflight(Config.t(), module(), [String.t()], keyword()) :: {:ok, keyword()} | {:error, Error.t()}
  def preflight(%Config{} = config, adapter, capabilities, opts \\ [])
      when is_atom(adapter) and is_list(capabilities) and is_list(opts) do
    policy = preflight_policy(opts)

    cond do
      policy == :off ->
        {:ok, Keyword.put_new(opts, :agent_quota_snapshot, nil)}

      @probe_capability in capabilities ->
        run_quota_probe(config, adapter, policy, opts)

      policy == :advisory ->
        snapshot = Snapshot.new(provider_kind: config.kind, status: :unsupported)
        emit_quota_completed(config, policy, snapshot, opts)
        {:ok, Keyword.put(opts, :agent_quota_snapshot, snapshot)}

      policy == :required ->
        quota_probe_unsupported(config, policy, opts)
    end
  end

  @spec preflight_policy(keyword()) :: :off | :advisory | :required
  def preflight_policy(opts) when is_list(opts) do
    opts
    |> Keyword.get(:agent_quota_preflight, default_preflight_policy())
    |> normalize_preflight_policy()
  end

  defp normalize_preflight_policy(:required), do: :required
  defp normalize_preflight_policy("required"), do: :required
  defp normalize_preflight_policy(:advisory), do: :advisory
  defp normalize_preflight_policy("advisory"), do: :advisory
  defp normalize_preflight_policy(_policy), do: :off

  defp default_preflight_policy do
    RuntimeConfig.agent_quota_settings()
    |> Map.get(:preflight, "off")
  rescue
    _error -> :off
  end

  defp run_quota_probe(%Config{} = config, adapter, policy, opts) do
    if function_exported?(adapter, :quota_probe, 3) do
      emit_quota_started(config, policy, opts)

      case adapter.quota_probe(config, Keyword.get(opts, :agent_credential_lease), opts) do
        {:ok, %Snapshot{} = snapshot} ->
          handle_probe_snapshot(config, policy, snapshot, opts)

        {:ok, snapshot} when is_map(snapshot) ->
          handle_probe_snapshot(config, policy, Snapshot.new(snapshot), opts)

        :unsupported ->
          handle_probe_unsupported(config, policy, opts)

        {:error, %Error{} = error} ->
          emit_quota_failed(config, policy, opts, error)
          {:error, error}

        {:error, reason} ->
          error = quota_probe_error(config, policy, reason)
          emit_quota_failed(config, policy, opts, error)
          {:error, error}

        other ->
          error = quota_probe_error(config, policy, {:unexpected_quota_probe_result, other})
          emit_quota_failed(config, policy, opts, error)
          {:error, error}
      end
    else
      quota_probe_not_implemented(config, policy, opts)
    end
  end

  defp handle_probe_snapshot(%Config{} = config, policy, %Snapshot{} = snapshot, opts) do
    snapshot =
      if snapshot.provider_kind in [nil, ""] do
        %{snapshot | provider_kind: config.kind}
      else
        snapshot
      end

    emit_quota_completed(config, policy, snapshot, opts)
    record_quota_snapshot(Keyword.get(opts, :agent_credential_lease), snapshot, opts)

    if policy == :required and not quota_admitted?(snapshot) do
      quota_probe_unavailable(config, policy, snapshot, opts)
    else
      {:ok, Keyword.put(opts, :agent_quota_snapshot, snapshot)}
    end
  end

  defp record_quota_snapshot(nil, _snapshot, _opts), do: :ok

  defp record_quota_snapshot(lease, %Snapshot{details: %{"rate_limits" => rate_limits}}, opts)
       when is_map(rate_limits) do
    CredentialStore.record_quota(lease, rate_limits, opts)
  end

  defp record_quota_snapshot(lease, %Snapshot{details: %{rate_limits: rate_limits}}, opts)
       when is_map(rate_limits) do
    CredentialStore.record_quota(lease, rate_limits, opts)
  end

  defp record_quota_snapshot(_lease, _snapshot, _opts), do: :ok

  defp handle_probe_unsupported(%Config{} = config, :advisory = policy, opts) do
    snapshot = Snapshot.new(provider_kind: config.kind, status: :unsupported)
    emit_quota_completed(config, policy, snapshot, opts)
    {:ok, Keyword.put(opts, :agent_quota_snapshot, snapshot)}
  end

  defp handle_probe_unsupported(%Config{} = config, :required = policy, opts) do
    snapshot = Snapshot.new(provider_kind: config.kind, status: :unsupported)
    quota_probe_unavailable(config, policy, snapshot, opts)
  end

  defp quota_admitted?(%Snapshot{status: status}), do: status in [:healthy, :limited]

  defp quota_probe_not_implemented(%Config{} = config, policy, opts) do
    error =
      Error.new(%{
        provider: config.kind,
        operation: :start_session,
        code: :agent_provider_not_implemented,
        message: "Agent quota probe is not implemented for this provider",
        retryable?: false,
        details: %{capability: @probe_capability, preflight: Atom.to_string(policy)}
      })

    emit_quota_failed(config, policy, opts, error)
    {:error, error}
  end

  defp quota_probe_unavailable(%Config{} = config, policy, %Snapshot{} = snapshot, opts) do
    error =
      Error.new(%{
        provider: config.kind,
        operation: :start_session,
        code: :agent_provider_quota_unavailable,
        message: "Quota preflight did not admit this provider run",
        retryable?: retryable_quota_status?(snapshot.status),
        details: %{
          capability: @probe_capability,
          preflight: Atom.to_string(policy),
          quota_status: Atom.to_string(snapshot.status),
          reset_at: snapshot.reset_at,
          retry_after_ms: snapshot.retry_after_ms
        }
      })

    emit_quota_failed(config, policy, opts, error)
    {:error, error}
  end

  defp quota_probe_unsupported(%Config{} = config, policy, opts) do
    error =
      Error.new(%{
        provider: config.kind,
        operation: :start_session,
        code: :agent_provider_quota_unavailable,
        message: "Quota preflight requires a provider quota probe, but the selected provider does not support one",
        retryable?: false,
        details: %{capability: @probe_capability, preflight: Atom.to_string(policy), quota_status: "unsupported"}
      })

    emit_quota_failed(config, policy, opts, error)
    {:error, error}
  end

  defp quota_probe_error(%Config{} = config, policy, reason) do
    Error.new(%{
      provider: config.kind,
      operation: :start_session,
      code: :agent_provider_quota_unavailable,
      message: "Agent quota probe failed",
      retryable?: true,
      details: %{
        capability: @probe_capability,
        preflight: Atom.to_string(policy),
        reason_summary: Redaction.summarize(reason, 256)
      }
    })
  end

  defp retryable_quota_status?(:exhausted), do: true
  defp retryable_quota_status?(:limited), do: true
  defp retryable_quota_status?(_status), do: false

  defp emit_quota_started(%Config{} = config, policy, opts) do
    ObsLogger.emit(
      :info,
      :agent_quota_probe_started,
      quota_event_fields(config, policy, opts, %{
        status: OperationStatus.started()
      })
    )
  end

  defp emit_quota_completed(%Config{} = config, policy, %Snapshot{} = snapshot, opts) do
    ObsLogger.emit(
      :info,
      :agent_quota_probe_completed,
      quota_event_fields(config, policy, opts, %{
        status: OperationStatus.completed(),
        quota_status: Atom.to_string(snapshot.status)
      })
    )
  end

  defp emit_quota_failed(%Config{} = config, policy, opts, %Error{} = error) do
    ObsLogger.emit(
      :error,
      :agent_quota_probe_failed,
      quota_event_fields(config, policy, opts, %{
        status: OperationStatus.failed(),
        quota_status: Map.get(error.details, :quota_status, "unsupported"),
        error_code: error.code,
        retryable: error.retryable?,
        error: error.message
      })
    )
  end

  defp quota_event_fields(%Config{} = config, policy, opts, extra) do
    %{
      component: "agent_quota",
      agent_provider_kind: config.kind,
      operation: "preflight",
      preflight: Atom.to_string(policy),
      run_id: Keyword.get(opts, :run_id),
      correlation_id: Keyword.get(opts, :run_id),
      issue_id: Keyword.get(opts, :issue_id) || map_value(Keyword.get(opts, :issue), :id),
      issue_identifier: Keyword.get(opts, :issue_identifier) || map_value(Keyword.get(opts, :issue), :identifier)
    }
    |> Map.merge(extra)
  end

  defp map_value(nil, _key), do: nil
  defp map_value(map, key) when is_map(map), do: Map.get(map, key)
  defp map_value(_value, _key), do: nil
end
