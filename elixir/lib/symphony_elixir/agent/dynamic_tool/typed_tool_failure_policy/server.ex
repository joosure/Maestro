defmodule SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.Server do
  @moduledoc false

  use GenServer

  alias SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy
  alias SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.{Config, FailureKey, FailureScope, RetryPolicy, State}

  @registered_name TypedToolFailurePolicy

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @registered_name))
  end

  @spec reset() :: :ok
  def reset do
    if running?() do
      GenServer.call(@registered_name, :reset)
    else
      :ok
    end
  end

  @spec state_value(atom()) :: term()
  def state_value(key) when is_atom(key) do
    if running?() do
      GenServer.call(@registered_name, {:state_value, key})
    end
  end

  @spec record_failure(FailureKey.t()) :: {pos_integer(), pos_integer()}
  def record_failure(%FailureKey{} = key) do
    if running?() do
      GenServer.call(@registered_name, {:record_failure, key})
    else
      {1, Config.threshold()}
    end
  end

  @spec reset_scope(FailureScope.t()) :: :ok
  def reset_scope(%FailureScope{} = scope) do
    if running?() do
      GenServer.call(@registered_name, {:reset_tool_scope, scope})
    else
      :ok
    end
  end

  @spec retry_policies(keyword()) :: %{String.t() => RetryPolicy.t()}
  def retry_policies(opts) when is_list(opts) do
    opts
    |> Keyword.get_lazy(:typed_tool_failure_retry_policies, fn ->
      state_value(:retry_policies) || Config.retry_policies()
    end)
    |> RetryPolicy.normalize_many!()
  end

  @spec resource_identity_fun(keyword()) :: function() | nil
  def resource_identity_fun(opts) when is_list(opts) do
    opts
    |> Keyword.get_lazy(:typed_tool_failure_resource_identity, fn ->
      state_value(:resource_identity) || Config.resource_identity()
    end)
    |> normalize_fun(2)
  end

  @spec audit_fields_fun(keyword()) :: function() | nil
  def audit_fields_fun(opts) when is_list(opts) do
    opts
    |> Keyword.get_lazy(:typed_tool_failure_audit_fields, fn ->
      state_value(:audit_fields) || Config.audit_fields()
    end)
    |> normalize_fun(2)
  end

  @impl true
  def init(opts) do
    {:ok, State.new!(opts, Config.defaults())}
  end

  @impl true
  def handle_call(:reset, _from, %State{} = state) do
    {:reply, :ok, State.reset_counts(state)}
  end

  def handle_call({:state_value, key}, _from, %State{} = state) do
    {:reply, State.value(state, key), state}
  end

  def handle_call({:record_failure, %FailureKey{} = key}, _from, %State{} = state) do
    {reply, state} = State.record_failure(state, key)
    {:reply, reply, state}
  end

  def handle_call({:reset_tool_scope, %FailureScope{} = scope}, _from, %State{} = state) do
    {:reply, :ok, State.reset_scope(state, scope)}
  end

  defp running?, do: not is_nil(Process.whereis(@registered_name))

  defp normalize_fun(fun, arity) when is_function(fun, arity), do: fun
  defp normalize_fun(_fun, _arity), do: nil
end
