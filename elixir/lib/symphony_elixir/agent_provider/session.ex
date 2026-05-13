defmodule SymphonyElixir.AgentProvider.Session do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Config

  @type t :: %__MODULE__{
          agent_provider_kind: String.t() | nil,
          provider_kind: String.t() | nil,
          provider_state: term(),
          provider_config: Config.t() | nil,
          agent_credential_lease: term(),
          agent_credential_material: term(),
          agent_process_pid: String.t() | nil,
          run_id: String.t() | nil,
          session_id: String.t() | nil,
          thread_id: String.t() | nil,
          workspace: Path.t() | nil,
          worker_host: String.t() | nil,
          metadata: map()
        }

  defstruct agent_provider_kind: nil,
            provider_kind: nil,
            provider_state: nil,
            provider_config: nil,
            agent_credential_lease: nil,
            agent_credential_material: nil,
            agent_process_pid: nil,
            run_id: nil,
            session_id: nil,
            thread_id: nil,
            workspace: nil,
            worker_host: nil,
            metadata: %{}

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    provider_kind = Map.get(attrs, :provider_kind) || Map.get(attrs, :agent_provider_kind)

    %__MODULE__{
      agent_provider_kind: provider_kind,
      provider_kind: provider_kind,
      provider_state: Map.get(attrs, :provider_state),
      provider_config: Map.get(attrs, :provider_config),
      agent_credential_lease: Map.get(attrs, :agent_credential_lease),
      agent_credential_material: Map.get(attrs, :agent_credential_material),
      agent_process_pid: Map.get(attrs, :agent_process_pid),
      run_id: Map.get(attrs, :run_id),
      session_id: Map.get(attrs, :session_id),
      thread_id: Map.get(attrs, :thread_id),
      workspace: Map.get(attrs, :workspace),
      worker_host: Map.get(attrs, :worker_host),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  @spec put_config(t(), Config.t()) :: t()
  def put_config(%__MODULE__{} = session, %Config{} = config), do: %{session | provider_config: config}
end
