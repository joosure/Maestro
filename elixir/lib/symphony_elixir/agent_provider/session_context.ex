defmodule SymphonyElixir.AgentProvider.SessionContext do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Config
  alias SymphonyElixir.AgentProvider.ConfigResolver
  alias SymphonyElixir.AgentProvider.Session

  @spec normalize_session(term()) :: Session.t()
  def normalize_session(%Session{} = session), do: session
  def normalize_session(session) when is_map(session), do: Session.new(session)

  @spec put_start_resources(Session.t(), keyword()) :: Session.t()
  def put_start_resources(%Session{} = session, opts) when is_list(opts) do
    %{
      session
      | agent_credential_lease: Keyword.get(opts, :agent_credential_lease),
        agent_credential_material: Keyword.get(opts, :agent_credential_material)
    }
  end

  @spec normalize_session_context(Session.t(), Config.t(), Path.t(), keyword()) :: Session.t()
  def normalize_session_context(%Session{} = session, %Config{} = config, workspace, opts) do
    %{
      session
      | agent_provider_kind: session.agent_provider_kind || config.kind,
        provider_kind: session.provider_kind || session.agent_provider_kind || config.kind,
        run_id: session.run_id || Keyword.get(opts, :run_id),
        workspace: session.workspace || workspace,
        worker_host: session.worker_host || Keyword.get(opts, :worker_host)
    }
  end

  @spec config_from_session(Session.t() | term(), keyword()) :: Config.t()
  def config_from_session(%Session{provider_config: %Config{} = config}, _opts), do: config

  def config_from_session(%Session{agent_provider_kind: kind}, opts) when is_binary(kind) do
    opts
    |> Keyword.put(:kind, kind)
    |> ConfigResolver.effective_config()
  end

  def config_from_session(_session, opts), do: ConfigResolver.effective_config(opts)
end
