defmodule SymphonyElixir.Workflow.TemplateRegistry do
  @moduledoc """
  Registry for bundled workflow template contracts.

  Workflow template files are user-facing configuration artifacts. This module
  owns the code-side contract for bundled template aliases and their expected
  structured front-matter fields.
  """

  alias SymphonyElixir.Agent.Credential.Store, as: CredentialStore
  alias SymphonyElixir.AgentProvider.Kinds, as: AgentProviderKinds
  alias SymphonyElixir.RepoProvider.Kinds, as: RepoProviderKinds
  alias SymphonyElixir.Tracker.Kinds, as: TrackerKinds
  alias SymphonyElixir.Workflow.Profiles.CodingPrDelivery
  alias SymphonyElixir.Workflow.Profiles.Triage

  @enforce_keys [
    :template_alias,
    :profile_kind,
    :profile_version,
    :tracker_kind,
    :repo_provider_kind,
    :agent_provider_kind
  ]
  defstruct [
    :template_alias,
    :profile_kind,
    :profile_version,
    :tracker_kind,
    :repo_provider_kind,
    :agent_provider_kind,
    :credential_ref
  ]

  @type t :: %__MODULE__{
          template_alias: String.t(),
          profile_kind: String.t(),
          profile_version: pos_integer(),
          tracker_kind: String.t(),
          repo_provider_kind: String.t(),
          agent_provider_kind: String.t(),
          credential_ref: String.t() | nil
        }

  @local_quickstart_alias "memory/no_repo/mock"
  @linear_github_opencode_alias "linear/github/opencode"
  @linear_github_codex_alias "linear/github/codex"
  @linear_github_claude_code_alias "linear/github/claude_code"
  @linear_github_codebuddy_code_alias "linear/github/codebuddy_code"
  @tapd_cnb_opencode_alias "tapd/cnb/opencode"
  @tapd_cnb_codebuddy_code_alias "tapd/cnb/codebuddy_code"
  @tapd_cnb_claude_code_alias "tapd/cnb/claude_code"
  @tapd_github_codex_alias "tapd/github/codex"
  @default_account_id "default"

  @spec local_quickstart_alias() :: String.t()
  def local_quickstart_alias, do: @local_quickstart_alias

  @spec entries() :: [t()]
  def entries do
    [
      triage_template(
        @local_quickstart_alias,
        TrackerKinds.memory(),
        RepoProviderKinds.memory(),
        AgentProviderKinds.mock()
      ),
      coding_pr_delivery_template(
        @linear_github_opencode_alias,
        TrackerKinds.linear(),
        RepoProviderKinds.github(),
        AgentProviderKinds.opencode()
      ),
      coding_pr_delivery_template(
        @linear_github_codex_alias,
        TrackerKinds.linear(),
        RepoProviderKinds.github(),
        AgentProviderKinds.codex()
      ),
      coding_pr_delivery_template(
        @linear_github_claude_code_alias,
        TrackerKinds.linear(),
        RepoProviderKinds.github(),
        AgentProviderKinds.claude_code()
      ),
      coding_pr_delivery_template(
        @linear_github_codebuddy_code_alias,
        TrackerKinds.linear(),
        RepoProviderKinds.github(),
        AgentProviderKinds.codebuddy_code(),
        credential_ref: default_credential_ref(AgentProviderKinds.codebuddy_code())
      ),
      coding_pr_delivery_template(
        @tapd_cnb_opencode_alias,
        TrackerKinds.tapd(),
        RepoProviderKinds.cnb(),
        AgentProviderKinds.opencode()
      ),
      coding_pr_delivery_template(
        @tapd_cnb_codebuddy_code_alias,
        TrackerKinds.tapd(),
        RepoProviderKinds.cnb(),
        AgentProviderKinds.codebuddy_code(),
        credential_ref: default_credential_ref(AgentProviderKinds.codebuddy_code())
      ),
      coding_pr_delivery_template(
        @tapd_cnb_claude_code_alias,
        TrackerKinds.tapd(),
        RepoProviderKinds.cnb(),
        AgentProviderKinds.claude_code()
      ),
      coding_pr_delivery_template(
        @tapd_github_codex_alias,
        TrackerKinds.tapd(),
        RepoProviderKinds.github(),
        AgentProviderKinds.codex()
      )
    ]
  end

  @spec aliases() :: [String.t()]
  def aliases, do: Enum.map(entries(), & &1.template_alias)

  @spec fetch(String.t()) :: {:ok, t()} | :error
  def fetch(template_alias) when is_binary(template_alias) do
    template_alias = normalize_alias(template_alias)

    case Enum.find(entries(), &(&1.template_alias == template_alias)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  @spec fetch_by(String.t(), String.t(), String.t()) :: {:ok, t()} | :error
  def fetch_by(tracker_kind, repo_provider_kind, agent_provider_kind)
      when is_binary(tracker_kind) and is_binary(repo_provider_kind) and is_binary(agent_provider_kind) do
    case Enum.find(entries(), &entry_matches?(&1, tracker_kind, repo_provider_kind, agent_provider_kind)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  @spec alias_for!(String.t(), String.t(), String.t()) :: String.t()
  def alias_for!(tracker_kind, repo_provider_kind, agent_provider_kind) do
    case fetch_by(tracker_kind, repo_provider_kind, agent_provider_kind) do
      {:ok, entry} ->
        entry.template_alias

      :error ->
        raise ArgumentError,
              "unknown bundled workflow template for tracker=#{inspect(tracker_kind)}, " <>
                "repo_provider=#{inspect(repo_provider_kind)}, agent_provider=#{inspect(agent_provider_kind)}"
    end
  end

  defp triage_template(template_alias, tracker_kind, repo_provider_kind, agent_provider_kind) do
    %__MODULE__{
      template_alias: template_alias,
      profile_kind: Triage.kind(),
      profile_version: Triage.version(),
      tracker_kind: tracker_kind,
      repo_provider_kind: repo_provider_kind,
      agent_provider_kind: agent_provider_kind
    }
  end

  defp coding_pr_delivery_template(template_alias, tracker_kind, repo_provider_kind, agent_provider_kind, opts \\ []) do
    %__MODULE__{
      template_alias: template_alias,
      profile_kind: CodingPrDelivery.kind(),
      profile_version: CodingPrDelivery.version(),
      tracker_kind: tracker_kind,
      repo_provider_kind: repo_provider_kind,
      agent_provider_kind: agent_provider_kind,
      credential_ref: Keyword.get(opts, :credential_ref)
    }
  end

  defp default_credential_ref(provider_kind) do
    CredentialStore.credential_ref(%{agent_provider_kind: provider_kind, id: @default_account_id})
  end

  defp normalize_alias(template_alias) do
    template_alias
    |> String.trim()
    |> String.replace_suffix(".md", "")
  end

  defp entry_matches?(entry, tracker_kind, repo_provider_kind, agent_provider_kind) do
    entry.tracker_kind == tracker_kind and
      entry.repo_provider_kind == repo_provider_kind and
      entry.agent_provider_kind == agent_provider_kind
  end
end
