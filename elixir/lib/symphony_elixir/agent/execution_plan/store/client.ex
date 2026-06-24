defmodule SymphonyElixir.Agent.ExecutionPlan.Store.Client do
  @moduledoc false

  @spec call(keyword(), module(), term(), term()) :: term()
  def call(opts, default_server, default, message) when is_list(opts) do
    opts
    |> Keyword.get(:server, default_server)
    |> call_server(default, message)
  end

  defp call_server(server, default, message) when is_atom(server) do
    case Process.whereis(server) do
      pid when is_pid(pid) -> safe_call(default, fn -> GenServer.call(server, message) end)
      _pid -> default
    end
  end

  defp call_server(server, default, message) when is_pid(server), do: safe_call(default, fn -> GenServer.call(server, message) end)
  defp call_server(_server, default, _message), do: default

  defp safe_call(default, fun) do
    fun.()
  catch
    :exit, _reason -> default
  end
end
