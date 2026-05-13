defmodule SymphonyElixir.Agent.Credential.Store.Settings do
  @moduledoc false

  alias SymphonyElixir.Config
  alias SymphonyElixir.Config.Schema.Credentials, as: CredentialSchema

  @type t :: %{
          enabled: boolean(),
          store_root: Path.t(),
          allow_host_auth_reuse: boolean(),
          rotation_strategy: String.t(),
          max_concurrent_leases_per_account: pos_integer(),
          lease_timeout_ms: pos_integer(),
          default_ttl_ms: pos_integer(),
          exhausted_cooldown_ms: pos_integer(),
          daily_token_budget: pos_integer() | nil
        }

  @spec resolve(keyword() | map() | nil) :: t()
  def resolve(opts \\ nil)

  def resolve(opts) when is_list(opts) do
    cond do
      is_map(Keyword.get(opts, :agent_credentials)) ->
        opts |> Keyword.fetch!(:agent_credentials) |> normalize()

      match?(%{agent: %{credentials: _}}, Keyword.get(opts, :settings)) ->
        opts |> Keyword.fetch!(:settings) |> Map.fetch!(:agent) |> Map.fetch!(:credentials) |> normalize()

      true ->
        current()
    end
  end

  def resolve(%{agent: %{credentials: credentials}}), do: normalize(credentials)
  def resolve(%{} = credentials), do: normalize(credentials)
  def resolve(_opts), do: current()

  @spec enabled?(keyword() | map() | nil) :: boolean()
  def enabled?(opts \\ nil), do: resolve(opts).enabled

  @spec normalize(map()) :: t()
  def normalize(settings) do
    defaults = CredentialSchema.defaults()

    %{
      enabled: setting(settings, :enabled, defaults),
      store_root: setting(settings, :store_root, defaults),
      allow_host_auth_reuse: setting(settings, :allow_host_auth_reuse, defaults),
      rotation_strategy: setting(settings, :rotation_strategy, defaults),
      max_concurrent_leases_per_account: setting(settings, :max_concurrent_leases_per_account, defaults),
      lease_timeout_ms: setting(settings, :lease_timeout_ms, defaults),
      default_ttl_ms: setting(settings, :default_ttl_ms, defaults),
      exhausted_cooldown_ms: setting(settings, :exhausted_cooldown_ms, defaults),
      daily_token_budget: setting(settings, :daily_token_budget, defaults)
    }
  end

  defp setting(settings, key, defaults) when is_map(settings) and is_atom(key) and is_map(defaults) do
    Map.get(settings, key, Map.get(settings, Atom.to_string(key), Map.fetch!(defaults, key)))
  end

  defp current do
    Config.settings!()
    |> Map.fetch!(:agent)
    |> Map.fetch!(:credentials)
    |> normalize()
  rescue
    _error ->
      normalize(%{})
  end
end
