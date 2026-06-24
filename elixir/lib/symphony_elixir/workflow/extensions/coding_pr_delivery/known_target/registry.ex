defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry do
  @moduledoc """
  Process-local registry of known issue/change-proposal targets.

  The registry keeps a bounded in-memory index for runtime access. Durable
  state is delegated to the Coding PR Delivery known-target storage port so the
  business payload stays outside platform storage infrastructure.
  """

  use GenServer

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Clock
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry.Options
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry.Retention
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry.StorageSync

  defmodule State do
    @moduledoc false

    alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget

    defstruct targets: %{},
              max_targets: nil,
              target_ttl_ms: nil,
              storage_opts: nil

    @type t :: %__MODULE__{
            targets: %{optional(String.t()) => KnownTarget.t()},
            max_targets: pos_integer(),
            target_ttl_ms: non_neg_integer() | nil,
            storage_opts: keyword() | nil
          }
  end

  @type register_result :: {:ok, KnownTarget.t()} | {:error, term()}

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    with {:ok, opts} <- Options.validate(opts),
         {:ok, _storage_opts} <- Options.storage_opts(opts) do
      case Keyword.fetch(opts, :name) do
        {:ok, nil} ->
          GenServer.start_link(__MODULE__, Keyword.delete(opts, :name))

        {:ok, name} ->
          GenServer.start_link(__MODULE__, opts, name: name)

        :error ->
          GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end
    else
      {:error, reason} -> {:error, {:known_target_registry_invalid_options, reason}}
    end
  end

  @spec register(term(), term()) :: register_result()
  def register(attrs, opts \\ []) do
    with {:ok, opts} <- Options.validate(opts),
         :ok <- Options.validate_attrs(attrs) do
      server = Keyword.get(opts, :server, __MODULE__)

      with_server(server, {:error, :known_target_registry_unavailable}, fn ->
        GenServer.call(server, {:register, attrs, opts})
      end)
    end
  end

  @spec update_observation(term(), term(), term()) :: register_result()
  def update_observation(issue_id, attrs, opts \\ []) do
    with {:ok, opts} <- Options.validate(opts),
         :ok <- Options.validate_issue_id(issue_id),
         :ok <- Options.validate_attrs(attrs) do
      server = Keyword.get(opts, :server, __MODULE__)

      with_server(server, {:error, :known_target_registry_unavailable}, fn ->
        GenServer.call(server, {:update_observation, issue_id, attrs, opts})
      end)
    end
  end

  @spec mark_enqueued(term(), term()) :: register_result()
  def mark_enqueued(issue_id, opts \\ []) do
    with {:ok, opts} <- Options.validate(opts),
         :ok <- Options.validate_issue_id(issue_id) do
      server = Keyword.get(opts, :server, __MODULE__)

      with_server(server, {:error, :known_target_registry_unavailable}, fn ->
        GenServer.call(server, {:mark_enqueued, issue_id, opts})
      end)
    end
  end

  @spec list_targets(term()) :: [KnownTarget.t()] | {:error, term()}
  def list_targets(opts \\ []) do
    with {:ok, opts} <- Options.validate(opts) do
      server = Keyword.get(opts, :server, __MODULE__)
      limit = Keyword.get(opts, :limit)

      with_server(server, [], fn ->
        GenServer.call(server, {:list_targets, limit, opts})
      end)
    end
  end

  @spec get(term(), term()) :: KnownTarget.t() | nil | {:error, term()}
  def get(issue_id, opts \\ []) do
    with {:ok, opts} <- Options.validate(opts),
         :ok <- Options.validate_issue_id(issue_id) do
      server = Keyword.get(opts, :server, __MODULE__)

      with_server(server, nil, fn ->
        GenServer.call(server, {:get, issue_id, opts})
      end)
    end
  end

  @impl true
  def init(opts) do
    case Options.storage_opts(opts) do
      {:ok, storage_opts} ->
        state = %State{
          max_targets: Options.max_targets(opts),
          target_ttl_ms: Options.target_ttl_ms(opts),
          storage_opts: storage_opts
        }

        case load_stored_targets(state, opts) do
          {:ok, state} -> {:ok, state}
          {:error, reason} -> {:stop, {:known_target_registry_storage_load_failed, reason}}
        end

      {:error, reason} ->
        {:stop, {:known_target_registry_invalid_options, reason}}
    end
  end

  @impl true
  def handle_call({:register, attrs, opts}, _from, %State{} = state) do
    with {:ok, state} <- Retention.prune_expired(state, opts),
         attrs = Options.normalize_attrs(attrs),
         {:ok, %KnownTarget{} = target} <- KnownTarget.new(attrs, opts),
         {:ok, target} <- merge_existing(state, target, opts),
         {:ok, updated_state} <- state |> put_target(target) |> Retention.enforce_target_limit(),
         :ok <- StorageSync.put(updated_state, target) do
      {:reply, {:ok, target}, updated_state}
    else
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:update_observation, issue_id, attrs, opts}, _from, %State{} = state) do
    with {:ok, state} <- Retention.prune_expired(state, opts),
         attrs = Options.normalize_attrs(attrs),
         %KnownTarget{} = existing <- Map.get(state.targets, issue_id) do
      attrs =
        attrs
        |> Map.put(Fields.issue_id(), issue_id)
        |> Map.put_new(Fields.tracker_kind(), existing.tracker_kind)
        |> Map.put_new(Fields.repo_provider_kind(), existing.repo_provider_kind)
        |> Map.put_new(Fields.repository(), existing.repository)

      case KnownTarget.new(attrs, opts) do
        {:ok, %KnownTarget{} = incoming} ->
          case KnownTarget.merge(existing, incoming, opts) do
            {:ok, %KnownTarget{} = target} ->
              updated_state = put_target(state, target)

              case StorageSync.put(updated_state, target) do
                :ok -> {:reply, {:ok, target}, updated_state}
                {:error, _reason} = error -> {:reply, error, state}
              end

            {:error, _reason} = error ->
              {:reply, error, state}
          end

        {:error, _reason} = error ->
          {:reply, error, state}
      end
    else
      nil ->
        {:reply, {:error, {:known_target_not_found, issue_id}}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:mark_enqueued, issue_id, opts}, _from, %State{} = state) do
    with {:ok, state} <- Retention.prune_expired(state, opts),
         %KnownTarget{} = existing <- Map.get(state.targets, issue_id),
         {:ok, now_ms} <- Clock.now_ms(opts) do
      target = %{existing | last_enqueued_at_ms: now_ms, updated_at_ms: now_ms}
      updated_state = put_target(state, target)

      case StorageSync.put(updated_state, target) do
        :ok -> {:reply, {:ok, target}, updated_state}
        {:error, _reason} = error -> {:reply, error, state}
      end
    else
      nil ->
        {:reply, {:error, {:known_target_not_found, issue_id}}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:list_targets, limit, opts}, _from, %State{} = state) do
    case Retention.prune_expired(state, opts) do
      {:ok, state} ->
        targets =
          state.targets
          |> Map.values()
          |> Enum.sort_by(& &1.updated_at_ms, :desc)
          |> maybe_take(limit)

        {:reply, targets, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:get, issue_id, opts}, _from, %State{} = state) do
    case Retention.prune_expired(state, opts) do
      {:ok, state} -> {:reply, Map.get(state.targets, issue_id), state}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call(:reset, _from, %State{} = state) do
    case StorageSync.reset(state) do
      :ok -> {:reply, :ok, %{state | targets: %{}}}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  defp load_stored_targets(%State{} = state, opts) do
    with {:ok, state} <- StorageSync.load(state),
         {:ok, state} <- Retention.prune_expired(state, opts),
         {:ok, state} <- Retention.enforce_target_limit(state) do
      {:ok, state}
    end
  end

  defp merge_existing(%State{} = state, %KnownTarget{issue_id: issue_id} = target, opts) do
    case Map.get(state.targets, issue_id) do
      %KnownTarget{} = existing -> KnownTarget.merge(existing, target, opts)
      nil -> {:ok, target}
    end
  end

  defp put_target(%State{} = state, %KnownTarget{issue_id: issue_id} = target) do
    %{state | targets: Map.put(state.targets, issue_id, target)}
  end

  defp maybe_take(targets, limit) when is_integer(limit) and limit >= 0, do: Enum.take(targets, limit)
  defp maybe_take(targets, _limit), do: targets

  defp with_server(server, fallback, fun) when is_atom(server) and is_function(fun, 0) do
    case Process.whereis(server) do
      pid when is_pid(pid) -> fun.()
      _other -> fallback
    end
  end

  defp with_server(server, _fallback, fun) when is_pid(server) and is_function(fun, 0), do: fun.()
  defp with_server(_server, fallback, _fun), do: fallback
end
