defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.TemplateCatalog.Contract do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Kinds, as: AgentProviderKinds
  alias SymphonyElixir.RepoProvider.Kinds, as: RepoProviderKinds
  alias SymphonyElixir.Tracker.Kinds, as: TrackerKinds

  @default_account_id "default"

  @type entry :: %{
          required(:template_alias) => String.t(),
          required(:tracker_kind) => String.t(),
          required(:repo_provider_kind) => String.t(),
          required(:agent_provider_kind) => String.t(),
          optional(:credential_account_id) => String.t()
        }

  @spec entries() :: [entry()]
  def entries do
    [
      entry("linear/github/opencode", TrackerKinds.linear(), RepoProviderKinds.github(), AgentProviderKinds.opencode()),
      entry("linear/github/codex", TrackerKinds.linear(), RepoProviderKinds.github(), AgentProviderKinds.codex()),
      entry("linear/github/claude_code", TrackerKinds.linear(), RepoProviderKinds.github(), AgentProviderKinds.claude_code()),
      entry(
        "linear/github/codebuddy_code",
        TrackerKinds.linear(),
        RepoProviderKinds.github(),
        AgentProviderKinds.codebuddy_code(),
        credential_account_id: @default_account_id
      ),
      entry("tapd/cnb/opencode", TrackerKinds.tapd(), RepoProviderKinds.cnb(), AgentProviderKinds.opencode()),
      entry(
        "tapd/cnb/codebuddy_code",
        TrackerKinds.tapd(),
        RepoProviderKinds.cnb(),
        AgentProviderKinds.codebuddy_code(),
        credential_account_id: @default_account_id
      ),
      entry("tapd/cnb/claude_code", TrackerKinds.tapd(), RepoProviderKinds.cnb(), AgentProviderKinds.claude_code()),
      entry("tapd/github/codex", TrackerKinds.tapd(), RepoProviderKinds.github(), AgentProviderKinds.codex())
    ]
  end

  defp entry(template_alias, tracker_kind, repo_provider_kind, agent_provider_kind, opts \\ []) do
    %{
      template_alias: template_alias,
      tracker_kind: tracker_kind,
      repo_provider_kind: repo_provider_kind,
      agent_provider_kind: agent_provider_kind
    }
    |> maybe_put_credential_account_id(opts)
  end

  defp maybe_put_credential_account_id(entry, opts) do
    case Keyword.fetch(opts, :credential_account_id) do
      {:ok, account_id} -> Map.put(entry, :credential_account_id, account_id)
      :error -> entry
    end
  end
end
