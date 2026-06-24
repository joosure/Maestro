defmodule SymphonyElixir.Workflow.Extension.Runtime.Scope do
  @moduledoc """
  Workflow scope contract for workflow-extension runtime state.

  The scope is used to partition extension-owned durable state. It must remain
  JSON-compatible so storage backends can hash, persist, and compare it without
  depending on Elixir runtime-only terms.
  """

  alias SymphonyElixir.Workflow.Extension.Canonical
  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.ErrorCodes
  alias SymphonyElixir.Workflow.ProfileRegistry

  @profile_kind_key "profile_kind"
  @profile_version_key "profile_version"
  @scope_source_key "scope_source"
  @workflow_config_hash_key "workflow_config_hash"

  @scope_source "workflow_runtime_context"
  @unknown_profile_kind "unknown"
  @unknown_profile_version 0

  @type t :: map()
  @type error :: %{
          required(:code) => String.t(),
          required(:message) => String.t(),
          required(:reason) => atom() | tuple(),
          optional(:value_type) => atom()
        }

  @spec new(term(), term()) :: {:ok, t()} | {:error, error()}
  def new(settings, opts \\ [])

  def new(settings, opts) when is_map(settings) and is_list(opts) do
    if Keyword.keyword?(opts) do
      scope_from_opts(settings, opts)
    else
      {:error, error(:opts_not_keyword, value_type: Diagnostics.detailed_type_atom(opts))}
    end
  end

  def new(settings, _opts) when not is_map(settings) do
    {:error, error(:settings_not_map, value_type: Diagnostics.detailed_type_atom(settings))}
  end

  def new(_settings, opts) do
    {:error, error(:opts_not_keyword, value_type: Diagnostics.detailed_type_atom(opts))}
  end

  @spec normalize(term()) :: {:ok, t()} | {:error, error()}
  def normalize(scope) when is_map(scope) do
    case json_map(scope) do
      {:ok, scope} -> {:ok, scope}
      {:error, reason} -> {:error, error(reason)}
    end
  end

  def normalize(scope) do
    {:error, error(:workflow_scope_not_map, value_type: Diagnostics.detailed_type_atom(scope))}
  end

  @spec profile_kind_key() :: String.t()
  def profile_kind_key, do: @profile_kind_key

  @spec profile_version_key() :: String.t()
  def profile_version_key, do: @profile_version_key

  @spec scope_source_key() :: String.t()
  def scope_source_key, do: @scope_source_key

  @spec workflow_config_hash_key() :: String.t()
  def workflow_config_hash_key, do: @workflow_config_hash_key

  @spec scope_source() :: String.t()
  def scope_source, do: @scope_source

  defp scope_from_opts(settings, opts) do
    if Keyword.has_key?(opts, :workflow_scope) do
      opts
      |> Keyword.fetch!(:workflow_scope)
      |> normalize()
    else
      default_scope(settings)
    end
  end

  defp default_scope(settings) do
    case workflow_config_hash(settings) do
      {:ok, workflow_config_hash} ->
        {:ok,
         settings
         |> profile_scope()
         |> Map.put(@workflow_config_hash_key, workflow_config_hash)}

      {:error, reason} ->
        {:error, canonical_error(reason)}
    end
  end

  defp profile_scope(settings) when is_map(settings) do
    settings
    |> Map.get(:workflow, %{})
    |> Map.get(:profile, %{})
    |> ProfileRegistry.resolve()
    |> case do
      {:ok, profile_context} ->
        %{
          @profile_kind_key => profile_context.kind,
          @profile_version_key => profile_context.version,
          @scope_source_key => @scope_source
        }

      {:error, _reason} ->
        %{
          @profile_kind_key => @unknown_profile_kind,
          @profile_version_key => @unknown_profile_version,
          @scope_source_key => @scope_source
        }
    end
  end

  defp workflow_config_hash(settings) when is_map(settings) do
    settings
    |> Map.get(:workflow, %{})
    |> workflow_identity_config()
    |> Canonical.runtime_config_hash()
  end

  defp workflow_identity_config(value) when is_struct(value), do: Map.from_struct(value)
  defp workflow_identity_config(value), do: value

  defp canonical_error(reason) do
    error(
      {:invalid_workflow_config_hash_input, Map.get(reason, :reason)},
      codec: Map.get(reason, :codec),
      value_type: Map.get(reason, :value_type)
    )
  end

  defp json_map(map) when is_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with {:ok, key} <- json_key(key),
           {:ok, value} <- json_value(value) do
        {:cont, {:ok, Map.put(acc, key, value)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp json_value(value) when is_struct(value), do: invalid_workflow_scope_value(value)
  defp json_value(value) when is_map(value), do: json_map(value)

  defp json_value(values) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case json_value(value) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp json_value(value) when is_binary(value), do: {:ok, value}
  defp json_value(value) when is_boolean(value), do: {:ok, value}
  defp json_value(value) when is_integer(value), do: {:ok, value}
  defp json_value(value) when is_float(value), do: {:ok, value}
  defp json_value(nil), do: {:ok, nil}
  defp json_value(value), do: invalid_workflow_scope_value(value)

  defp json_key(key) when is_binary(key), do: {:ok, key}
  defp json_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}

  defp json_key(key),
    do: {:error, {:invalid_workflow_scope_key, Diagnostics.detailed_type_atom(key)}}

  defp invalid_workflow_scope_value(value),
    do: {:error, {:invalid_workflow_scope_value, Diagnostics.detailed_type_atom(value)}}

  defp error(reason, fields \\ []) do
    %{
      code: ErrorCodes.invalid_runtime_context(),
      message: "Workflow extension runtime context is invalid.",
      reason: reason
    }
    |> Map.merge(Map.new(fields))
  end
end
