defmodule SymphonyElixir.AgentProvider.ClaudeCode.AppServer.EventFields do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.AppServer.EventFields, as: AppServerEventFields

  @spec build(Path.t(), String.t() | nil, map() | nil, map()) :: map()
  def build(workspace, worker_host, issue, extra) when is_map(extra) do
    AppServerEventFields.build(base_fields(), workspace, worker_host, issue, extra, compact_issue_fields?: false)
  end

  defp base_fields do
    %{
      component: "agent_provider.claude_code",
      agent_provider_kind: "claude_code"
    }
  end
end
