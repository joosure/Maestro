defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.StateStoreBackend do
  @moduledoc """
  StateStore backend for Coding PR Delivery known targets.

  The backend stores known targets as extension-owned state records.
  """

  @behaviour SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage
  @behaviour SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.AdminBackend

  alias SymphonyElixir.Workflow.Extension.StateStore
  alias SymphonyElixir.Workflow.Extension.StateStore.Record, as: StateStoreRecord
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Payload
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.{Scope, Validator}

  @impl true
  def load(opts) do
    with {:ok, opts} <- Validator.validate_opts(opts),
         {:ok, records} <- list_records(opts) do
      decode_records(records, opts)
    end
  end

  @impl true
  def put(%KnownTarget{} = target, opts) do
    with {:ok, opts} <- Validator.validate_opts(opts),
         {:ok, workflow_scope} <- Scope.fetch(opts),
         {:ok, payload} <- Payload.to_map(target) do
      attrs = %{
        extension_id: extension_id(),
        extension_version: extension_version(),
        workflow_scope: workflow_scope,
        state_type: Payload.schema_id(),
        state_key: target.issue_id,
        payload_schema: Payload.schema_id(),
        payload: payload
      }

      StateStore.put(attrs, state_store_opts(opts))
    end
    |> case do
      {:ok, %StateStoreRecord{}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def put(target, opts) do
    with {:ok, _opts} <- Validator.validate_opts(opts) do
      Validator.validate_target(target)
    end
  end

  @impl true
  def put_many(targets, opts) do
    with {:ok, opts} <- Validator.validate_opts(opts),
         :ok <- Validator.validate_targets(targets) do
      Enum.reduce_while(targets, :ok, fn %KnownTarget{} = target, :ok ->
        case put(target, opts) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  @impl true
  def delete(issue_id, opts) do
    with {:ok, opts} <- Validator.validate_opts(opts),
         :ok <- Validator.validate_issue_id(issue_id),
         {:ok, workflow_scope} <- Scope.fetch(opts) do
      StateStore.delete(extension_id(), workflow_scope, Payload.schema_id(), issue_id, state_store_opts(opts))
    end
  end

  @impl true
  def reset(opts) do
    with {:ok, opts} <- Validator.validate_opts(opts) do
      opts
      |> list_records(Keyword.put(state_store_opts(opts), :include_expired?, true))
      |> case do
        {:ok, records} -> delete_records(records, opts)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp decode_records(records, opts) when is_list(records) do
    records
    |> Enum.reduce_while({:ok, []}, fn %StateStoreRecord{payload: payload}, {:ok, targets} ->
      case Payload.from_map(payload, opts) do
        {:ok, %KnownTarget{} = target} -> {:cont, {:ok, [target | targets]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, targets} -> {:ok, Enum.reverse(targets)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_records(records, opts) when is_list(records) do
    Enum.reduce_while(records, :ok, fn %StateStoreRecord{state_key: state_key}, :ok ->
      case delete(state_key, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp list_records(opts), do: list_records(opts, state_store_opts(opts))

  defp list_records(opts, state_store_opts) do
    with {:ok, workflow_scope} <- Scope.fetch(opts) do
      StateStore.list(extension_id(), workflow_scope, Payload.schema_id(), state_store_opts)
    end
  end

  defp state_store_opts(opts) do
    opts
    |> Keyword.take([:now_ms])
  end

  defp extension_id, do: CodingPrDelivery.id()
  defp extension_version, do: CodingPrDelivery.version()
end
