defmodule SymphonyWorkerDaemon.BridgeProxy do
  @moduledoc false

  use GenServer

  alias SymphonyWorkerDaemon.BridgeProxy.{ProxyOptions, Requester, UpstreamPolicy}

  @loopback_ip {127, 0, 0, 1}
  @base_url_env "SYMPHONY_DYNAMIC_TOOL_BRIDGE_BASE_URL"

  @type runtime :: %{
          required(:pid) => pid(),
          required(:base_url) => String.t(),
          required(:env) => map(),
          required(:port) => pos_integer()
        }

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      type: :worker
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec start_from_request(map(), keyword()) :: {:ok, runtime() | nil} | {:error, term()}
  def start_from_request(request, opts \\ []) when is_map(request) and is_list(opts) do
    case Map.get(request, "dynamic_tool_bridge") do
      bridge_spec when is_map(bridge_spec) ->
        with :ok <- ProxyOptions.ensure_enabled(opts),
             {:ok, pid} <- start_linked_proxy(Keyword.merge(opts, bridge_spec: bridge_spec)),
             env <- env(pid) do
          {:ok,
           %{
             pid: pid,
             base_url: Map.fetch!(env, @base_url_env),
             env: env,
             port: port(pid)
           }}
        end

      _bridge_spec ->
        {:ok, nil}
    end
  end

  defp start_linked_proxy(opts) when is_list(opts) do
    with {:ok, pid} <- GenServer.start(__MODULE__, opts) do
      Process.link(pid)
      {:ok, pid}
    end
  end

  @spec env(GenServer.server()) :: map()
  def env(server), do: GenServer.call(server, :env)

  @spec port(GenServer.server()) :: pos_integer()
  def port(server), do: GenServer.call(server, :port)

  @spec stop(term()) :: :ok
  def stop(nil), do: :ok

  def stop(%{pid: pid}) when is_pid(pid), do: stop(pid)

  def stop(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
    :ok
  catch
    :exit, _reason -> :ok
  end

  def stop(_runtime), do: :ok

  @impl true
  @spec init(keyword()) :: {:ok, map()} | {:stop, term()}
  def init(opts) when is_list(opts) do
    bridge_spec = Keyword.fetch!(opts, :bridge_spec)

    with {:ok, upstream_base_url} <- UpstreamPolicy.base_url(bridge_spec, opts),
         {:ok, upstream_token} <- ProxyOptions.upstream_token(bridge_spec),
         {:ok, port} <- ProxyOptions.port(opts),
         session_token <- Keyword.get(opts, :session_token, Ecto.UUID.generate()),
         plug_opts <- ProxyOptions.plug_opts(upstream_base_url, upstream_token, session_token, opts),
         {:ok, bandit_pid} <- start_bandit(port, plug_opts) do
      {:ok,
       %{
         bandit_pid: bandit_pid,
         port: port,
         session_token: session_token,
         upstream_base_url: upstream_base_url,
         env: ProxyOptions.provider_env(port, session_token)
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  @spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()}
  def handle_call(:env, _from, state), do: {:reply, state.env, state}
  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  @impl true
  @spec terminate(term(), map()) :: :ok
  def terminate(_reason, %{bandit_pid: bandit_pid}) when is_pid(bandit_pid) do
    Supervisor.stop(bandit_pid)
    :ok
  catch
    :exit, _reason -> :ok
  end

  def terminate(_reason, _state), do: :ok

  defp start_bandit(port, plug_opts) do
    Bandit.start_link(
      plug: {SymphonyWorkerDaemon.BridgeProxy.RouterPlug, plug_opts},
      scheme: :http,
      ip: @loopback_ip,
      port: port
    )
  end

  @spec default_requester(atom(), String.t(), [{String.t(), String.t()}], map() | nil, map()) ::
          {:ok, pos_integer(), term()} | {:error, term()}
  defdelegate default_requester(method, url, headers, body, request_opts), to: Requester, as: :request
end
