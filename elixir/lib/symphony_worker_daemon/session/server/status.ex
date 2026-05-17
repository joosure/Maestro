defmodule SymphonyWorkerDaemon.Session.Server.Status do
  @moduledoc false

  alias SymphonyWorkerDaemon.Session.Status, as: SessionStatus

  @spec running() :: String.t()
  defdelegate running(), to: SessionStatus

  @spec exited() :: String.t()
  defdelegate exited(), to: SessionStatus

  @spec failed() :: String.t()
  defdelegate failed(), to: SessionStatus

  @spec cleaned() :: String.t()
  defdelegate cleaned(), to: SessionStatus

  @spec stopped() :: String.t()
  defdelegate stopped(), to: SessionStatus

  @spec lost() :: String.t()
  defdelegate lost(), to: SessionStatus

  @spec terminal_statuses() :: [String.t()]
  defdelegate terminal_statuses(), to: SessionStatus

  @spec successful_terminal_statuses() :: [String.t()]
  defdelegate successful_terminal_statuses(), to: SessionStatus

  @spec terminal?(term()) :: boolean()
  defdelegate terminal?(status), to: SessionStatus

  @spec successful_terminal?(term()) :: boolean()
  defdelegate successful_terminal?(status), to: SessionStatus

  @spec exit_status_name(integer()) :: String.t()
  defdelegate exit_status_name(status), to: SessionStatus

  @spec put_stop_reason(map(), term()) :: map()
  defdelegate put_stop_reason(state, reason), to: SessionStatus
end
