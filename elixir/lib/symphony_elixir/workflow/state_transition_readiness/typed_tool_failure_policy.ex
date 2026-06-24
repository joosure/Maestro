defmodule SymphonyElixir.Workflow.StateTransitionReadiness.TypedToolFailurePolicy do
  @moduledoc """
  Workflow-readiness retry policy injected into the generic Dynamic Tool failure engine.
  """

  alias SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.{ResourceIdentity, RetryPolicy}
  alias SymphonyElixir.Workflow.Extension.Registry, as: ExtensionRegistry

  @spec agent_options() :: keyword()
  def agent_options do
    [
      retry_policies: retry_policies(),
      resource_identity: &resource_identity/2,
      audit_fields: &audit_fields/2
    ]
  end

  @spec retry_policies() :: map()
  def retry_policies do
    ExtensionRegistry.entries()
    |> case do
      {:ok, extension_entries} ->
        extension_entries
        |> Enum.reduce(%{}, &Map.merge(&2, extension_retry_policies(&1)))
        |> RetryPolicy.normalize_many!()

      {:error, reason} ->
        raise ArgumentError, "Invalid workflow extension typed-tool failure retry-policy registry: #{inspect(reason)}"
    end
  end

  @spec resource_identity(map(), term()) :: ResourceIdentity.t() | nil
  def resource_identity(runtime_metadata, arguments) do
    cond do
      value = scoped_value(runtime_metadata, :resource_id) ->
        ResourceIdentity.new!(scoped_value(runtime_metadata, :resource_kind) || "resource", value)

      value = scoped_value(runtime_metadata, :issue_id) || argument_value(arguments, "issue_id") || argument_value(arguments, :issue_id) ->
        ResourceIdentity.new!("tracker_issue", value)

      identity = extension_resource_identity(runtime_metadata, arguments) ->
        identity

      value = argument_value(arguments, "branch") || argument_value(arguments, :branch) ->
        ResourceIdentity.new!("repo_branch", value)

      value = scoped_value(runtime_metadata, :session_id) ->
        ResourceIdentity.new!("agent_session", value)

      true ->
        nil
    end
  end

  @spec audit_fields(String.t(), term()) :: map()
  def audit_fields("tracker_issue", issue_id), do: %{issue_id: issue_id}
  def audit_fields(_resource_kind, _resource_id), do: %{}

  defp scoped_value(runtime_metadata, key) when is_map(runtime_metadata) and is_atom(key) do
    Map.get(runtime_metadata, key) || Map.get(runtime_metadata, Atom.to_string(key))
  end

  defp scoped_value(_runtime_metadata, _key), do: nil

  defp argument_value(arguments, key) when is_map(arguments), do: Map.get(arguments, key)
  defp argument_value(_arguments, _key), do: nil

  defp extension_retry_policies(extension_entry) do
    module = extension_entry.module

    if function_exported?(module, :typed_tool_failure_retry_policies, 0) do
      case safe_call(module, :typed_tool_failure_retry_policies, []) do
        {:ok, policies} when is_map(policies) ->
          policies

        {:ok, policies} ->
          raise ArgumentError,
                "Workflow extension #{inspect(module)} returned invalid typed-tool failure retry policies: #{diagnostic_type(policies)}"

        {:error, callback_error} ->
          raise ArgumentError,
                "Workflow extension #{inspect(module)} failed to return typed-tool failure retry policies: #{inspect(callback_error)}"
      end
    else
      %{}
    end
  end

  defp extension_resource_identity(runtime_metadata, arguments) do
    case ExtensionRegistry.entries() do
      {:ok, extension_entries} ->
        Enum.find_value(extension_entries, fn extension_entry ->
          extension_resource_identity(extension_entry, runtime_metadata, arguments)
        end)

      {:error, _reason} ->
        nil
    end
  end

  defp extension_resource_identity(extension_entry, runtime_metadata, arguments) do
    module = extension_entry.module

    if function_exported?(module, :typed_tool_failure_resource_identity, 2) do
      case safe_call(module, :typed_tool_failure_resource_identity, [runtime_metadata, arguments]) do
        {:ok, {kind, value}} when is_binary(kind) and not is_nil(value) ->
          ResourceIdentity.new!(kind, value)

        {:ok, nil} ->
          nil

        {:ok, _invalid_identity} ->
          nil

        {:error, _callback_error} ->
          nil
      end
    end
  end

  defp safe_call(module, callback, args) do
    {:ok, apply(module, callback, args)}
  rescue
    error ->
      {:error, %{kind: :error, error: Exception.message(error)}}
  catch
    kind, reason ->
      {:error, %{kind: kind, reason: inspect(reason)}}
  end

  defp diagnostic_type(value) when is_atom(value) and not is_nil(value), do: "atom"
  defp diagnostic_type(value) when is_binary(value), do: "string"
  defp diagnostic_type(value) when is_boolean(value), do: "boolean"
  defp diagnostic_type(value) when is_integer(value), do: "integer"
  defp diagnostic_type(value) when is_float(value), do: "float"
  defp diagnostic_type(value) when is_list(value), do: "list"
  defp diagnostic_type(value) when is_map(value), do: "map"
  defp diagnostic_type(nil), do: "nil"
  defp diagnostic_type(_value), do: "term"
end
