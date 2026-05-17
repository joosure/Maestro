defmodule SymphonyElixir.Agent.Credential do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.{Lease, LeaseRequest, Material, Store}
  alias SymphonyElixir.AgentProvider.{Config, Error}
  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Observability.OperationStatus
  alias SymphonyElixir.Observability.Redaction
  alias SymphonyElixir.Workflow.CapabilityNames

  @managed_capability CapabilityNames.agent_credentials_managed()

  @spec prepare_provider_start(Config.t(), module(), [String.t()], keyword()) ::
          {:ok, keyword()} | {:error, Error.t()}
  def prepare_provider_start(%Config{} = config, adapter, capabilities, opts \\ [])
      when is_atom(adapter) and is_list(capabilities) and is_list(opts) do
    case credential_ref(config) do
      nil ->
        {:ok,
         opts
         |> Keyword.put_new(:agent_credential_lease, nil)
         |> Keyword.put_new(:agent_credential_material, nil)}

      credential_ref ->
        if @managed_capability in capabilities do
          managed_credentials_prepare(config, adapter, credential_ref, opts)
        else
          managed_credentials_unsupported(config, credential_ref, opts)
        end
    end
  end

  @spec credential_ref(Config.t()) :: String.t() | nil
  def credential_ref(%Config{options: options}) when is_map(options) do
    options
    |> Map.get("credential_ref")
    |> normalize_optional_string()
  end

  @spec credential_ref_summary(String.t() | nil) :: String.t() | nil
  def credential_ref_summary(nil), do: nil
  def credential_ref_summary(ref) when is_binary(ref), do: Redaction.summarize(ref, 128)

  @spec material_env(Material.t() | term()) :: map()
  def material_env(%Material{env: env}) when is_map(env), do: env
  def material_env(_material), do: %{}

  @spec cleanup_material(Material.t() | term()) :: :ok | {:error, term()}
  def cleanup_material(%Material{cleanup: cleanup}) when is_list(cleanup) do
    cleanup
    |> Enum.reduce([], fn instruction, failures ->
      case cleanup_instruction(instruction) do
        :ok -> failures
        {:error, reason} -> [reason | failures]
      end
    end)
    |> case do
      [] -> :ok
      failures -> {:error, {:credential_material_cleanup_failed, Enum.reverse(failures)}}
    end
  end

  def cleanup_material(_material), do: :ok

  @spec release_provider_start(Config.t(), term(), keyword()) :: :ok
  def release_provider_start(%Config{} = config, session, opts \\ []) when is_list(opts) do
    material = session_material(session)
    cleanup_result = cleanup_material(material)

    case session_lease(session) do
      %Lease{} = lease ->
        case cleanup_result do
          :ok -> :ok
          {:error, reason} -> emit_credential_release_failed(config, lease, opts, reason)
        end

        case Store.release(lease, opts) do
          :ok ->
            emit_credential_released(config, lease, opts)

          {:error, reason} ->
            emit_credential_release_failed(config, lease, opts, reason)
        end

        :ok

      _lease ->
        case cleanup_result do
          :ok -> :ok
          {:error, reason} -> emit_credential_material_cleanup_failed(config, opts, reason)
        end

        :ok
    end
  end

  @spec record_session_usage(term(), map() | nil, keyword()) :: :ok
  def record_session_usage(session, usage, opts \\ []) when is_list(opts) do
    case session_lease(session) do
      %Lease{} = lease -> Store.record_usage(lease, usage, nil, opts)
      _lease -> :ok
    end
  end

  @spec record_session_success(term(), keyword()) :: :ok
  def record_session_success(session, opts \\ []) when is_list(opts) do
    case session_lease(session) do
      %Lease{} = lease -> Store.mark_success(lease, opts)
      _lease -> :ok
    end
  end

  @spec mark_session_quota_exhausted(term(), term(), keyword()) :: :ok
  def mark_session_quota_exhausted(session, reason, opts \\ []) when is_list(opts) do
    case session_lease(session) do
      %Lease{} = lease -> Store.mark_exhausted(lease, reason, opts)
      _lease -> :ok
    end
  end

  defp managed_credentials_prepare(%Config{} = config, adapter, credential_ref, opts) do
    emit_credential_requested(config, credential_ref, opts)

    if function_exported?(adapter, :materialize_credential, 3) do
      case acquire_lease(config, credential_ref, opts) do
        {:ok, lease} ->
          materialize_lease(config, adapter, lease, credential_ref, opts)

        {:error, %Error{} = error} ->
          emit_credential_failed(config, credential_ref, opts, error)
          {:error, error}
      end
    else
      managed_credentials_not_implemented(config, credential_ref, opts)
    end
  end

  defp materialize_lease(%Config{} = config, adapter, %Lease{} = lease, credential_ref, opts) do
    case adapter.materialize_credential(config, lease, opts) do
      {:ok, %Material{} = material} ->
        emit_credential_acquired(config, lease, credential_ref, opts)

        {:ok,
         opts
         |> Keyword.put(:agent_credential_lease, lease)
         |> Keyword.put(:agent_credential_material, material)}

      {:ok, material} when is_map(material) ->
        material = Material.new(material)
        emit_credential_acquired(config, lease, credential_ref, opts)

        {:ok,
         opts
         |> Keyword.put(:agent_credential_lease, lease)
         |> Keyword.put(:agent_credential_material, material)}

      :unsupported ->
        managed_credentials_unsupported(config, credential_ref, opts)

      {:error, %Error{} = error} ->
        Store.release(lease, opts)
        emit_credential_failed(config, credential_ref, opts, error)
        {:error, error}

      {:error, reason} ->
        Store.release(lease, opts)
        error = credential_error(config, credential_ref, reason)
        emit_credential_failed(config, credential_ref, opts, error)
        {:error, error}

      other ->
        Store.release(lease, opts)
        error = credential_error(config, credential_ref, {:unexpected_materialize_credential_result, other})
        emit_credential_failed(config, credential_ref, opts, error)
        {:error, error}
    end
  end

  defp managed_credentials_not_implemented(%Config{} = config, credential_ref, opts) do
    error =
      Error.new(%{
        provider: config.kind,
        operation: :start_session,
        code: :agent_provider_not_implemented,
        message: "Managed agent credentials are not implemented for this provider",
        retryable?: false,
        details: credential_details(credential_ref, @managed_capability)
      })

    emit_credential_failed(config, credential_ref, opts, error)
    {:error, error}
  end

  defp managed_credentials_unsupported(%Config{} = config, credential_ref, opts) do
    error =
      Error.new(%{
        provider: config.kind,
        operation: :start_session,
        code: :agent_provider_capability_unsupported,
        message: "Selected provider does not support managed agent credentials",
        retryable?: false,
        details: credential_details(credential_ref, @managed_capability)
      })

    emit_credential_failed(config, credential_ref, opts, error)
    {:error, error}
  end

  defp credential_error(%Config{} = config, credential_ref, reason) do
    Error.new(%{
      provider: config.kind,
      operation: :start_session,
      code: :agent_provider_credential_unavailable,
      message: "Managed agent credential materialization failed",
      retryable?: true,
      details:
        credential_details(credential_ref, @managed_capability)
        |> Map.put(:reason_summary, Redaction.summarize(reason, 256))
    })
  end

  defp build_lease(%Config{} = config, credential_ref, opts) do
    request = lease_request(config, credential_ref, opts)

    Lease.new(%{
      id: lease_id(config, opts),
      provider_kind: request.provider_kind,
      credential_ref_summary: credential_ref_summary(request.credential_ref),
      account_id: account_id_from_ref(request.credential_ref),
      metadata: %{
        run_id: request.run_id,
        issue_id: request.issue_id,
        worker_pool: request.worker_pool,
        purpose: request.purpose
      }
    })
  end

  defp lease_request(%Config{} = config, credential_ref, opts) do
    LeaseRequest.new(%{
      provider_kind: config.kind,
      credential_ref: credential_ref,
      run_id: Keyword.get(opts, :run_id),
      issue_id: Keyword.get(opts, :issue_id) || map_value(Keyword.get(opts, :issue), :id),
      worker_pool: runtime_value(opts, :worker_pool),
      purpose: Keyword.get(opts, :credential_lease_purpose, :run)
    })
  end

  defp acquire_lease(%Config{} = config, credential_ref, opts) do
    if Store.enabled?(opts) do
      case Store.acquire(config.kind, credential_ref, opts) do
        {:ok, %Lease{} = lease} ->
          {:ok, lease}

        {:error, reason} ->
          {:error, credential_error(config, credential_ref, reason)}
      end
    else
      {:ok, build_lease(config, credential_ref, opts)}
    end
  end

  defp lease_id(%Config{} = config, opts) do
    base =
      opts
      |> Keyword.get(:run_id)
      |> case do
        run_id when is_binary(run_id) and run_id != "" -> run_id
        _ -> Integer.to_string(System.unique_integer([:positive]))
      end

    "agent-credential-" <> config.kind <> "-" <> base
  end

  defp account_id_from_ref("credential://" <> rest) do
    rest
    |> String.split("/", parts: 2)
    |> List.last()
    |> normalize_optional_string()
  end

  defp account_id_from_ref(_credential_ref), do: nil

  defp emit_credential_requested(%Config{} = config, credential_ref, opts) do
    ObsLogger.emit(
      :info,
      :agent_credential_lease_requested,
      credential_event_fields(config, credential_ref, opts, %{
        operation: "acquire_lease",
        status: "requested"
      })
    )
  end

  defp emit_credential_acquired(%Config{} = config, %Lease{} = lease, credential_ref, opts) do
    ObsLogger.emit(
      :info,
      :agent_credential_lease_acquired,
      credential_event_fields(config, credential_ref, opts, %{
        operation: "acquire_lease",
        status: "acquired",
        lease_id: lease.id,
        account_id_summary: credential_ref_summary(lease.account_id)
      })
    )
  end

  defp emit_credential_released(%Config{} = config, %Lease{} = lease, opts) do
    ObsLogger.emit(
      :info,
      :agent_credential_lease_released,
      %{
        component: "agent_credential",
        agent_provider_kind: config.kind,
        operation: "release_lease",
        status: "released",
        run_id: Keyword.get(opts, :run_id) || lease.metadata[:run_id],
        correlation_id: Keyword.get(opts, :run_id) || lease.metadata[:run_id],
        issue_id: Keyword.get(opts, :issue_id) || lease.metadata[:issue_id],
        issue_identifier: Keyword.get(opts, :issue_identifier),
        worker_pool: Keyword.get(opts, :worker_pool) || lease.metadata[:worker_pool],
        credential_ref_summary: lease.credential_ref_summary,
        lease_id: lease.id,
        account_id_summary: credential_ref_summary(lease.account_id)
      }
    )
  end

  defp emit_credential_release_failed(%Config{} = config, %Lease{} = lease, opts, reason) do
    ObsLogger.emit(
      :error,
      :agent_credential_lease_release_failed,
      %{
        component: "agent_credential",
        agent_provider_kind: config.kind,
        operation: "release_lease",
        status: OperationStatus.failed(),
        run_id: Keyword.get(opts, :run_id) || lease.metadata[:run_id],
        correlation_id: Keyword.get(opts, :run_id) || lease.metadata[:run_id],
        issue_id: Keyword.get(opts, :issue_id) || lease.metadata[:issue_id],
        issue_identifier: Keyword.get(opts, :issue_identifier),
        worker_pool: Keyword.get(opts, :worker_pool) || lease.metadata[:worker_pool],
        credential_ref_summary: lease.credential_ref_summary,
        lease_id: lease.id,
        account_id_summary: credential_ref_summary(lease.account_id),
        error: Redaction.summarize(reason, 256)
      }
    )
  end

  defp emit_credential_failed(%Config{} = config, credential_ref, opts, %Error{} = error) do
    ObsLogger.emit(
      :error,
      :agent_credential_lease_failed,
      credential_event_fields(config, credential_ref, opts, %{
        operation: "acquire_lease",
        status: OperationStatus.failed(),
        error_code: error.code,
        retryable: error.retryable?,
        error: error.message
      })
    )
  end

  defp credential_event_fields(%Config{} = config, credential_ref, opts, extra) do
    %{
      component: "agent_credential",
      agent_provider_kind: config.kind,
      run_id: Keyword.get(opts, :run_id),
      correlation_id: Keyword.get(opts, :run_id),
      issue_id: Keyword.get(opts, :issue_id) || map_value(Keyword.get(opts, :issue), :id),
      issue_identifier: Keyword.get(opts, :issue_identifier) || map_value(Keyword.get(opts, :issue), :identifier),
      worker_pool: runtime_value(opts, :worker_pool),
      credential_ref_summary: credential_ref_summary(credential_ref),
      credential_source_class: credential_source_class(credential_ref)
    }
    |> Map.merge(extra)
  end

  defp credential_details(credential_ref, capability) do
    %{
      credential_ref_summary: credential_ref_summary(credential_ref),
      capability: capability
    }
  end

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_value), do: nil

  defp credential_source_class("credential://" <> _rest), do: "credential"
  defp credential_source_class(_credential_ref), do: "unknown"

  defp runtime_value(opts, key) when is_list(opts) do
    case Keyword.get(opts, :agent_runtime_target) do
      %{^key => value} -> value
      _ -> opts |> Keyword.get(:provider_runtime_context, %{}) |> map_value(key)
    end
  end

  defp session_lease(%{agent_credential_lease: %Lease{} = lease}), do: lease
  defp session_lease(_session), do: nil

  defp session_material(%{agent_credential_material: %Material{} = material}), do: material
  defp session_material(_session), do: nil

  defp cleanup_instruction({:rm_rf, path}) when is_binary(path), do: cleanup_rm_rf(path)
  defp cleanup_instruction(%{"rm_rf" => path}) when is_binary(path), do: cleanup_rm_rf(path)
  defp cleanup_instruction(%{rm_rf: path}) when is_binary(path), do: cleanup_rm_rf(path)
  defp cleanup_instruction(other), do: {:error, {:invalid_credential_material_cleanup_instruction, Redaction.summarize(other, 128)}}

  defp cleanup_rm_rf(path) when is_binary(path) do
    case File.rm_rf(path) do
      {:ok, _paths} -> :ok
      {:error, reason, failed_path} -> {:error, {:credential_material_rm_rf_failed, failed_path, reason}}
    end
  end

  defp map_value(nil, _key), do: nil
  defp map_value(map, key) when is_map(map), do: Map.get(map, key)
  defp map_value(_value, _key), do: nil

  defp emit_credential_material_cleanup_failed(%Config{} = config, opts, reason) do
    ObsLogger.emit(
      :error,
      :agent_credential_material_cleanup_failed,
      %{
        component: "agent_credential",
        agent_provider_kind: config.kind,
        operation: "cleanup_material",
        status: OperationStatus.failed(),
        run_id: Keyword.get(opts, :run_id),
        correlation_id: Keyword.get(opts, :run_id),
        issue_id: Keyword.get(opts, :issue_id) || map_value(Keyword.get(opts, :issue), :id),
        issue_identifier: Keyword.get(opts, :issue_identifier) || map_value(Keyword.get(opts, :issue), :identifier),
        worker_pool: runtime_value(opts, :worker_pool),
        error: Redaction.summarize(reason, 256)
      }
    )
  end
end
