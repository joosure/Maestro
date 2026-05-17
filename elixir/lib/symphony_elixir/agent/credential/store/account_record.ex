defmodule SymphonyElixir.Agent.Credential.Store.AccountRecord do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.Store.{Normalization, Paths, RateLimits, State}
  alias SymphonyElixir.AgentProvider.ClaudeCode.CredentialEnv, as: ClaudeCredentialEnv
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.AgentProvider.OpenCode.CredentialEnv, as: OpenCodeCredentialEnv

  @claude_code_kind Kinds.claude_code()
  @claude_oauth_token_credential_kind ClaudeCredentialEnv.oauth_token_credential_kind()
  @opencode_env_token_credential_kind OpenCodeCredentialEnv.env_token_credential_kind()
  @opencode_kind Kinds.opencode()

  @spec normalize(String.t(), Path.t(), map(), map(), map()) :: map()
  def normalize(provider_kind, account_dir, metadata, state, settings) do
    %{
      agent_provider_kind: provider_kind,
      id: Map.get(metadata, "id") || Path.basename(account_dir),
      email: Normalization.normalize_optional_string(Map.get(metadata, "email")),
      enabled: Map.get(metadata, "enabled", true),
      credential_kind: Map.get(metadata, "credential_kind") || default_credential_kind(provider_kind),
      env_name: Normalization.normalize_optional_string(Map.get(metadata, "env_name")),
      worker_host: Normalization.normalize_optional_string(Map.get(metadata, "worker_host")),
      state: State.effective_state(State.normalize_state(Map.get(state, "state")), metadata),
      account_dir: account_dir,
      auth_dir: Path.join(account_dir, "auth"),
      secret_file: Path.join(account_dir, "secret"),
      paused_until: Normalization.normalize_optional_string(Map.get(metadata, "paused_until")),
      paused_reason: Normalization.normalize_optional_string(Map.get(metadata, "paused_reason")),
      exhausted_until: Normalization.normalize_optional_string(Map.get(state, "exhausted_until")),
      failure_reason: Normalization.normalize_optional_string(Map.get(state, "failure_reason")),
      latest_quota: Map.get(state, "latest_quota"),
      last_success_at: Normalization.normalize_optional_string(Map.get(state, "last_success_at")),
      token_totals: Map.get(state, "token_totals", State.default_token_totals()),
      rate_limit_periods: Map.get(state, "rate_limit_periods", %{}),
      active_leases: State.prune_expired_leases(Map.get(state, "active_leases", %{}), DateTime.utc_now()),
      daily_token_budget:
        Normalization.positive_integer_value(Map.get(metadata, "daily_token_budget")) ||
          settings.daily_token_budget
    }
  end

  @spec merge_metadata(map(), String.t(), String.t(), map()) :: map()
  def merge_metadata(existing, provider_kind, id, attrs) do
    now = Normalization.now_iso()

    existing
    |> Map.merge(%{
      "agent_provider_kind" => provider_kind,
      "id" => id,
      "enabled" => Map.get(attrs, "enabled", Map.get(existing, "enabled", true)),
      "credential_kind" =>
        Map.get(
          attrs,
          "credential_kind",
          Map.get(existing, "credential_kind", default_credential_kind(provider_kind))
        ),
      "env_name" => Map.get(attrs, "env_name", Map.get(existing, "env_name")),
      "email" => Map.get(attrs, "email", Map.get(existing, "email")),
      "worker_host" => Map.get(attrs, "worker_host", Map.get(existing, "worker_host")),
      "daily_token_budget" => Map.get(attrs, "daily_token_budget", Map.get(existing, "daily_token_budget")),
      "created_at" => Map.get(existing, "created_at", now),
      "updated_at" => now
    })
    |> Normalization.drop_nil_values()
  end

  @spec pause_metadata(map(), map()) :: {map(), String.t()}
  def pause_metadata(metadata, attrs) do
    reason = Map.get(attrs, "reason") || "manually paused"
    paused_until = Normalization.normalize_datetime_string(Map.get(attrs, "until"))

    metadata =
      metadata
      |> Map.put("paused_until", paused_until)
      |> Map.put("paused_reason", reason)
      |> Map.put("updated_at", Normalization.now_iso())
      |> Normalization.drop_nil_values()

    {metadata, reason}
  end

  @spec resume_metadata(map()) :: map()
  def resume_metadata(metadata) do
    metadata
    |> Map.delete("paused_until")
    |> Map.delete("paused_reason")
    |> Map.put("enabled", true)
    |> Map.put("updated_at", Normalization.now_iso())
  end

  @spec set_enabled_metadata(map(), boolean()) :: map()
  def set_enabled_metadata(metadata, enabled) when is_boolean(enabled) do
    metadata
    |> Map.put("enabled", enabled)
    |> Map.put("updated_at", Normalization.now_iso())
  end

  @spec summary(map() | nil) :: map() | nil
  def summary(nil), do: nil

  def summary(account) when is_map(account) do
    %{
      agent_provider_kind: Map.get(account, :agent_provider_kind),
      id: Map.get(account, :id),
      email: Map.get(account, :email),
      state: Map.get(account, :state),
      enabled: Map.get(account, :enabled),
      credential_kind: Map.get(account, :credential_kind),
      env_name: Map.get(account, :env_name),
      worker_host: Map.get(account, :worker_host),
      exhausted_until: Map.get(account, :exhausted_until),
      paused_until: Map.get(account, :paused_until),
      failure_reason: Map.get(account, :failure_reason),
      latest_quota: Map.get(account, :latest_quota),
      latest_reset_at: RateLimits.latest_reset_at(account),
      token_totals: Map.get(account, :token_totals),
      usage_periods_csv: Paths.usage_periods_csv_path(account)
    }
  end

  @spec default_credential_kind(String.t()) :: String.t()
  def default_credential_kind(@claude_code_kind), do: @claude_oauth_token_credential_kind
  def default_credential_kind(@opencode_kind), do: @opencode_env_token_credential_kind
  def default_credential_kind(_provider_kind), do: "provider_profile"
end
