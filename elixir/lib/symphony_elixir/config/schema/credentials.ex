defmodule SymphonyElixir.Config.Schema.Credentials do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @default_enabled false
  @default_store_root Path.expand("~/.symphony/agent_credentials")
  @default_allow_host_auth_reuse false
  @default_rotation_strategy "usage_aware_round_robin"
  @default_max_concurrent_leases_per_account 1
  @default_lease_timeout_ms 10_000
  @default_ttl_ms 3_600_000
  @default_exhausted_cooldown_ms 300_000
  @default_daily_token_budget nil
  @rotation_strategies ["usage_aware_round_robin", "least_usage"]
  @defaults %{
    enabled: @default_enabled,
    store_root: @default_store_root,
    allow_host_auth_reuse: @default_allow_host_auth_reuse,
    rotation_strategy: @default_rotation_strategy,
    max_concurrent_leases_per_account: @default_max_concurrent_leases_per_account,
    lease_timeout_ms: @default_lease_timeout_ms,
    default_ttl_ms: @default_ttl_ms,
    exhausted_cooldown_ms: @default_exhausted_cooldown_ms,
    daily_token_budget: @default_daily_token_budget
  }

  @primary_key false
  embedded_schema do
    field(:enabled, :boolean, default: @default_enabled)
    field(:store_root, :string, default: @default_store_root)
    field(:allow_host_auth_reuse, :boolean, default: @default_allow_host_auth_reuse)
    field(:rotation_strategy, :string, default: @default_rotation_strategy)
    field(:max_concurrent_leases_per_account, :integer, default: @default_max_concurrent_leases_per_account)
    field(:lease_timeout_ms, :integer, default: @default_lease_timeout_ms)
    field(:default_ttl_ms, :integer, default: @default_ttl_ms)
    field(:exhausted_cooldown_ms, :integer, default: @default_exhausted_cooldown_ms)
    field(:daily_token_budget, :integer)
  end

  @spec defaults() :: map()
  def defaults, do: @defaults

  @spec default_store_root() :: String.t()
  def default_store_root, do: @default_store_root

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(
      attrs,
      [
        :enabled,
        :store_root,
        :allow_host_auth_reuse,
        :rotation_strategy,
        :max_concurrent_leases_per_account,
        :lease_timeout_ms,
        :default_ttl_ms,
        :exhausted_cooldown_ms,
        :daily_token_budget
      ],
      empty_values: []
    )
    |> validate_inclusion(:rotation_strategy, @rotation_strategies)
    |> validate_number(:max_concurrent_leases_per_account, greater_than: 0)
    |> validate_number(:lease_timeout_ms, greater_than: 0)
    |> validate_number(:default_ttl_ms, greater_than: 0)
    |> validate_number(:exhausted_cooldown_ms, greater_than: 0)
    |> validate_number(:daily_token_budget, greater_than: 0)
  end
end
