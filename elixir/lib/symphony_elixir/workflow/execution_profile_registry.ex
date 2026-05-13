defmodule SymphonyElixir.Workflow.ExecutionProfileRegistry do
  @moduledoc """
  Boot-configured runtime execution-profile registry.

  Repository-controlled workflow config may select execution-profile names, but
  it cannot define registry entries or runtime handlers.
  """

  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Entry
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Resolver
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Selection
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Source
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Values
  alias SymphonyElixir.Workflow.ProfileRegistry

  @type resolved_profile :: ProfileRegistry.resolved_profile()
  @type selected_execution_profile :: Selection.selected_execution_profile()

  @spec fetch_entries() :: {:ok, [Entry.t()]} | {:error, term()}
  defdelegate fetch_entries(), to: Source

  @spec validate_registry() :: :ok | {:error, term()}
  defdelegate validate_registry(), to: Source

  @spec effective_allowed_execution_profiles(resolved_profile()) :: [String.t()]
  defdelegate effective_allowed_execution_profiles(profile_context), to: Resolver

  @spec resolve(resolved_profile(), String.t(), atom()) ::
          {:ok, {:profile_owned, String.t()} | {:runtime_registered, Entry.t()}} | {:error, term()}
  defdelegate resolve(profile_context, execution_profile, action), to: Resolver

  @spec required_capabilities(resolved_profile(), String.t(), atom()) :: [String.t()]
  defdelegate required_capabilities(profile_context, execution_profile, action), to: Resolver

  @spec selected_execution_profiles(map(), resolved_profile()) :: [selected_execution_profile()]
  defdelegate selected_execution_profiles(settings, profile_context), to: Selection

  @spec validate_selected_execution_profiles(map(), resolved_profile()) :: :ok | {:error, term()}
  defdelegate validate_selected_execution_profiles(settings, profile_context), to: Selection

  @spec normalize_name(term()) :: String.t() | nil
  defdelegate normalize_name(value), to: Values
end
