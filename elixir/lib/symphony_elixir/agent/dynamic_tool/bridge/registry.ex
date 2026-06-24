defmodule SymphonyElixir.Agent.DynamicTool.Bridge.Registry do
  @moduledoc """
  Stores session-scoped Dynamic Tool bridge contexts by bearer token.
  """

  use GenServer

  alias SymphonyElixir.Agent.DynamicTool.Context

  @name __MODULE__

  @type token :: String.t()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, @name))

  @spec register(Context.t() | map()) :: token()
  def register(tool_context) when is_map(tool_context) do
    tool_context = Context.from_opts(tool_context: tool_context)
    token = random_token()
    :ok = GenServer.call(@name, {:register, token, tool_context})
    token
  end

  @spec unregister(term()) :: :ok
  def unregister(token) when is_binary(token), do: GenServer.cast(@name, {:unregister, token})
  def unregister(_token), do: :ok

  @spec fetch(term()) :: {:ok, Context.t()} | :error
  def fetch(token) when is_binary(token), do: GenServer.call(@name, {:fetch, token})
  def fetch(_token), do: :error

  @spec registered?(term()) :: boolean()
  def registered?(token) when is_binary(token), do: match?({:ok, _context}, fetch(token))
  def registered?(_token), do: false

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:register, token, tool_context}, _from, state) do
    {:reply, :ok, Map.put(state, token, tool_context)}
  end

  def handle_call({:fetch, token}, _from, state) do
    case Map.fetch(state, token) do
      {:ok, tool_context} -> {:reply, {:ok, tool_context}, state}
      :error -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_cast({:unregister, token}, state), do: {:noreply, Map.delete(state, token)}

  defp random_token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
end
