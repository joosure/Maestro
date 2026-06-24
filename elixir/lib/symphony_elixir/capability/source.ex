defmodule SymphonyElixir.Capability.Source do
  @moduledoc """
  Behaviour for domain-owned capability catalogs.

  Capability strings are external protocol values. Their ownership stays with
  the domain that provides the capability; platform code aggregates source
  modules instead of centralizing every domain vocabulary in one context.
  """

  @type capability :: String.t()

  @callback capabilities() :: [capability()]
  @callback typed_tool_capabilities() :: [capability()]
  @callback merge_gate_capabilities() :: [capability()]
  @callback diagnostic_capabilities() :: [capability()]
  @callback known_provider_unavailable_capabilities() :: [capability()]

  @optional_callbacks typed_tool_capabilities: 0,
                      merge_gate_capabilities: 0,
                      diagnostic_capabilities: 0,
                      known_provider_unavailable_capabilities: 0
end
