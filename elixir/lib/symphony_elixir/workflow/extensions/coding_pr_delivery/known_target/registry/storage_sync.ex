defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry.StorageSync do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry.State
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage, as: KnownTargetStorage
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.Admin, as: KnownTargetStorageAdmin

  @spec load(State.t()) :: {:ok, State.t()} | {:error, term()}
  def load(%State{storage_opts: nil} = state), do: {:ok, state}

  def load(%State{storage_opts: storage_opts} = state) when is_list(storage_opts) do
    case KnownTargetStorage.load(storage_opts) do
      {:ok, targets} when is_list(targets) ->
        targets =
          Map.new(targets, fn %KnownTarget{} = target ->
            {target.issue_id, target}
          end)

        {:ok, %{state | targets: targets}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec put(State.t(), KnownTarget.t()) :: :ok | {:error, term()}
  def put(%State{storage_opts: nil}, %KnownTarget{}), do: :ok

  def put(%State{storage_opts: storage_opts}, %KnownTarget{} = target) when is_list(storage_opts) do
    case KnownTargetStorage.put(target, storage_opts) do
      :ok -> :ok
      {:error, _reason} = error -> error
    end
  end

  @spec delete_targets(State.t(), [String.t()]) :: :ok | {:error, term()}
  def delete_targets(%State{}, []), do: :ok
  def delete_targets(%State{storage_opts: nil}, _issue_ids), do: :ok

  def delete_targets(%State{storage_opts: storage_opts}, issue_ids) when is_list(storage_opts) do
    Enum.reduce_while(issue_ids, :ok, fn issue_id, :ok ->
      case KnownTargetStorage.delete(issue_id, storage_opts) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @spec reset(State.t()) :: :ok | {:error, term()}
  def reset(%State{storage_opts: nil}), do: :ok

  def reset(%State{storage_opts: storage_opts}) when is_list(storage_opts) do
    case KnownTargetStorageAdmin.reset(storage_opts) do
      :ok -> :ok
      {:error, _reason} = error -> error
    end
  end
end
