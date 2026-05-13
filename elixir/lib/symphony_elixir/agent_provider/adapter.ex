defmodule SymphonyElixir.AgentProvider.Adapter do
  @moduledoc """
  Contract for pluggable AI coding agent providers.
  """

  alias SymphonyElixir.Agent.{Credential, Quota}
  alias SymphonyElixir.AgentProvider.{Config, Error, EventSummary, Session, TurnResult}

  @type capability ::
          String.t()

  @callback kind() :: String.t()
  @callback defaults() :: map()
  @callback validate_options(map()) :: :ok | {:error, term()}
  @callback finalize_options(map()) :: map()
  @callback validate_config(Config.t()) :: :ok | {:error, Error.t() | term()}
  @callback prepare_workspace(Config.t(), Path.t(), keyword()) :: :ok | {:error, Error.t() | term()}
  @callback start_session(Config.t(), Path.t(), keyword()) :: {:ok, Session.t()} | {:error, Error.t() | term()}
  @callback run_turn(Config.t(), Session.t(), String.t(), map(), keyword()) ::
              {:ok, TurnResult.t()} | {:error, Error.t() | term()}
  @callback stop_session(Config.t(), Session.t(), keyword()) :: :ok | {:error, Error.t() | term()}
  @callback session_stop_options(Config.t(), term(), term()) :: keyword()
  @callback failed_session_stop_options(Config.t(), term(), String.t()) :: keyword()
  @callback summarize_message(term()) :: EventSummary.t()
  @callback session_log_event?(String.t(), String.t()) :: boolean()
  @callback workspace_automation_destination_dir() :: String.t()
  @callback capabilities() :: [capability()]
  @callback dynamic_tool_inventory_opts() :: keyword()
  @callback account_login(String.t(), keyword(), keyword() | map() | nil) :: {:ok, map()} | {:error, term()}
  @callback account_verify(map(), keyword(), keyword() | map() | nil) :: {:ok, map()} | {:error, term()}
  @callback materialize_credential(Config.t(), Credential.Lease.t(), keyword()) ::
              {:ok, Credential.Material.t()} | {:error, Error.t() | term()} | :unsupported
  @callback quota_probe(Config.t(), Credential.Lease.t() | nil, keyword()) ::
              {:ok, Quota.Snapshot.t()} | {:error, Error.t() | term()} | :unsupported

  @optional_callbacks account_login: 3,
                      account_verify: 3,
                      dynamic_tool_inventory_opts: 0,
                      materialize_credential: 3,
                      quota_probe: 3
end
