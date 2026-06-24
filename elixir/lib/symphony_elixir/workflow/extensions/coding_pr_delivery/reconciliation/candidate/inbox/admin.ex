defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox.Admin do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox.{Error, Options}

  @spec reset(keyword()) :: :ok | {:error, map()}
  def reset(opts \\ []) do
    with {:ok, opts} <- Options.keyword_opts(opts, :options_not_keyword),
         {:ok, server} <- Options.server(opts, Inbox) do
      call_server(server)
    end
  end

  defp call_server(server) when is_atom(server) do
    case Process.whereis(server) do
      pid when is_pid(pid) -> GenServer.call(pid, :reset)
      _other -> {:error, Error.unavailable(server)}
    end
  end

  defp call_server(server) when is_pid(server), do: GenServer.call(server, :reset)
end
