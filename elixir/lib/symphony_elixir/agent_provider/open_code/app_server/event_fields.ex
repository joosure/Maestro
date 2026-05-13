defmodule SymphonyElixir.AgentProvider.OpenCode.AppServer.EventFields do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.AppServer.EventFields, as: AppServerEventFields

  @spec event(Path.t(), String.t() | nil, map() | nil, map()) :: map()
  def event(workspace, worker_host, issue, extra) when is_map(extra) do
    AppServerEventFields.build(base_fields(), workspace, worker_host, issue, extra, compact_issue_fields?: false)
  end

  defp base_fields do
    %{
      component: "agent_provider.opencode",
      agent_provider_kind: "opencode"
    }
  end
end
