defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry.Admin do
  @moduledoc """
  Administrative controls for the Coding PR Delivery known-target registry.

  Destructive operations are kept out of the runtime business facade so normal
  extension code can register, read, and update targets without also exposing
  storage-wide reset capabilities.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry.Options

  @spec reset(term()) :: :ok | {:error, term()}
  def reset(opts \\ []) do
    with {:ok, opts} <- Options.validate(opts) do
      server = Keyword.get(opts, :server, Registry)

      with_server(server, :ok, fn ->
        GenServer.call(server, :reset)
      end)
    end
  end

  defp with_server(server, fallback, fun) when is_function(fun, 0) do
    cond do
      is_pid(server) and Process.alive?(server) ->
        fun.()

      is_atom(server) and not is_nil(Process.whereis(server)) ->
        fun.()

      true ->
        fallback
    end
  catch
    :exit, _reason -> fallback
  end
end
