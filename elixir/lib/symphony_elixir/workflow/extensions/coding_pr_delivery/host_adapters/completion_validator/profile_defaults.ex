defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.CompletionValidator.ProfileDefaults do
  @moduledoc false

  alias SymphonyElixir.Workflow.ProfileRegistry

  @type resolved_profile :: ProfileRegistry.resolved_profile()

  @spec default_profile_config() :: map()
  def default_profile_config, do: ProfileRegistry.default_profile_config()

  @spec resolve_profile(map()) :: {:ok, resolved_profile()} | {:error, term()}
  def resolve_profile(profile), do: ProfileRegistry.resolve(profile)

  @spec completion_contract(module(), map()) :: map()
  def completion_contract(profile_module, profile_options) do
    ProfileRegistry.completion_contract(profile_module, profile_options)
  end
end
