defmodule SymphonyElixir.Workflow.Template do
  @moduledoc """
  Stable facade for workflow template lookup and asset resolution.

  This module is the public boundary for workflow-template consumers and
  contributors. `Workflow.Template.Entry` is the public contribution record;
  registry, resolver, path-rule, and OTP `priv/` asset-root mechanics stay
  behind this facade unless a module is implementing or testing the template
  mechanism itself.
  """

  alias SymphonyElixir.Workflow.Template.Assets
  alias SymphonyElixir.Workflow.Template.Entry
  alias SymphonyElixir.Workflow.Template.Registry
  alias SymphonyElixir.Workflow.Template.Resolver

  @type entry :: Entry.t()

  @spec local_quickstart_alias() :: String.t()
  def local_quickstart_alias, do: Registry.local_quickstart_alias()

  @spec entries() :: [entry()]
  def entries, do: Registry.entries()

  @spec aliases() :: [String.t()]
  def aliases, do: Registry.aliases()

  @spec fetch(String.t()) :: {:ok, entry()} | :error
  def fetch(template_alias), do: Registry.fetch(template_alias)

  @spec fetch_by(String.t(), String.t(), String.t()) :: {:ok, entry()} | :error
  def fetch_by(tracker_kind, repo_provider_kind, agent_provider_kind),
    do: Registry.fetch_by(tracker_kind, repo_provider_kind, agent_provider_kind)

  @spec alias_for!(String.t(), String.t(), String.t()) :: String.t()
  def alias_for!(tracker_kind, repo_provider_kind, agent_provider_kind),
    do: Registry.alias_for!(tracker_kind, repo_provider_kind, agent_provider_kind)

  @spec platform_asset_root() :: Path.t()
  def platform_asset_root, do: Registry.platform_asset_root()

  @spec app_priv_root!(Path.t(), keyword()) :: Path.t()
  def app_priv_root!(relative_dir, opts \\ []), do: Assets.app_priv_root!(relative_dir, opts)

  @spec entry!(keyword() | map()) :: entry()
  def entry!(attrs), do: Registry.entry!(attrs)

  @spec asset_path!(Path.t(), String.t()) :: Path.t()
  def asset_path!(asset_root, template_alias), do: Registry.asset_path!(asset_root, template_alias)

  @spec root() :: Path.t()
  def root, do: Resolver.root()

  @spec roots() :: [Path.t()]
  def roots, do: Resolver.roots()

  @spec root_for(Path.t()) :: Path.t()
  def root_for(path), do: Resolver.root_for(path)

  @spec paths() :: [Path.t()]
  def paths, do: Resolver.paths()

  @spec partial_roots() :: [Path.t()]
  def partial_roots, do: Resolver.partial_roots()

  @spec partial_allowed?(Path.t()) :: boolean()
  def partial_allowed?(path), do: Resolver.partial_allowed?(path)

  @spec resolve(String.t()) :: {:ok, Path.t()} | {:error, String.t()}
  def resolve(template_alias), do: Resolver.resolve(template_alias)
end
