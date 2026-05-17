defmodule SymphonyWorkerDaemon.CommandPolicy.CapabilityContract do
  @moduledoc """
  Health capability envelope for Worker Daemon command execution policy.
  """

  @kind_key "kind"
  @scope_key "scope"
  @available_key "available"
  @command_key "command"
  @path_key "path"
  @name_key "name"
  @executable_policy_kind "executable_policy"
  @executable_kind "executable"
  @any_scope "any"

  @spec kind_key() :: String.t()
  def kind_key, do: @kind_key

  @spec scope_key() :: String.t()
  def scope_key, do: @scope_key

  @spec available_key() :: String.t()
  def available_key, do: @available_key

  @spec command_key() :: String.t()
  def command_key, do: @command_key

  @spec path_key() :: String.t()
  def path_key, do: @path_key

  @spec name_key() :: String.t()
  def name_key, do: @name_key

  @spec executable_policy_kind() :: String.t()
  def executable_policy_kind, do: @executable_policy_kind

  @spec executable_kind() :: String.t()
  def executable_kind, do: @executable_kind

  @spec any_scope() :: String.t()
  def any_scope, do: @any_scope

  @spec executable_policy_any() :: map()
  def executable_policy_any do
    %{
      @kind_key => @executable_policy_kind,
      @scope_key => @any_scope,
      @available_key => true
    }
  end

  @spec executable_available(map()) :: map()
  def executable_available(spec) when is_map(spec) do
    Map.merge(%{@kind_key => @executable_kind, @available_key => true}, spec)
  end

  @spec executable_unavailable(String.t()) :: map()
  def executable_unavailable(command) when is_binary(command) do
    %{
      @kind_key => @executable_kind,
      @command_key => command,
      @name_key => Path.basename(command),
      @available_key => false
    }
  end
end
