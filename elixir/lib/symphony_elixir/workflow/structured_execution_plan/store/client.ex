defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Client do
  @moduledoc """
  GenServer client boundary for the workflow structured-plan Store facade.
  """

  @spec call(atom() | pid() | term(), term(), term()) :: term()
  def call(server, default, message) when is_atom(server) do
    case Process.whereis(server) do
      pid when is_pid(pid) -> safe_call(default, fn -> GenServer.call(server, message) end)
      _pid -> default
    end
  end

  def call(server, default, message) when is_pid(server), do: safe_call(default, fn -> GenServer.call(server, message) end)
  def call(_server, default, _message), do: default

  defp safe_call(default, fun) do
    fun.()
  catch
    :exit, _reason -> default
  end
end
