defmodule SymphonyElixir.Workflow.RouteRef do
  @moduledoc """
  Profile-scoped route identity.

  Route keys are only unique inside a workflow profile kind/version. Code that
  parses, validates, stores, or displays a route should carry this profile scope
  so shared names such as `review` remain unambiguous across profiles.
  """

  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RoutePolicy

  @enforce_keys [:profile_kind, :profile_version, :route_key]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          profile_kind: String.t(),
          profile_version: pos_integer(),
          route_key: atom()
        }

  @type profile_context :: map()

  @spec new(profile_context(), term()) :: {:ok, t()} | {:error, term()}
  def new(profile_context, route_key) do
    with {:ok, {profile_kind, profile_version, profile_module}} <- resolve_profile(profile_context),
         {:ok, route_key} <- normalize_route_key(route_key, profile_module, profile_kind, profile_version) do
      {:ok,
       %__MODULE__{
         profile_kind: profile_kind,
         profile_version: profile_version,
         route_key: route_key
       }}
    end
  end

  @spec new!(profile_context(), term()) :: t()
  def new!(profile_context, route_key) do
    case new(profile_context, route_key) do
      {:ok, route_ref} -> route_ref
      {:error, reason} -> raise ArgumentError, "invalid workflow route ref: #{inspect(reason)}"
    end
  end

  @spec event_fields(t()) :: map()
  def event_fields(%__MODULE__{} = route_ref) do
    %{
      workflow_profile: route_ref.profile_kind,
      workflow_profile_version: route_ref.profile_version,
      workflow_route_key: route_key_name(route_ref)
    }
  end

  @spec event_fields(profile_context(), term()) :: map()
  def event_fields(profile_context, route_key) do
    case new(profile_context, route_key) do
      {:ok, route_ref} -> event_fields(route_ref)
      {:error, _reason} -> best_effort_event_fields(profile_context, route_key)
    end
  end

  @spec transition_target_event_fields(t() | term()) :: map()
  def transition_target_event_fields(%__MODULE__{} = route_ref) do
    %{
      workflow_transition_target_route_key: route_key_name(route_ref)
    }
  end

  def transition_target_event_fields(route_key) do
    %{workflow_transition_target_route_key: route_key_name(route_key)}
  end

  @spec string_fields(t()) :: map()
  def string_fields(%__MODULE__{} = route_ref) do
    %{
      "workflow_profile" => route_ref.profile_kind,
      "workflow_profile_version" => route_ref.profile_version,
      "workflow_route_key" => route_key_name(route_ref)
    }
  end

  @spec string_fields(profile_context(), term()) :: map()
  def string_fields(profile_context, route_key) do
    case new(profile_context, route_key) do
      {:ok, route_ref} -> string_fields(route_ref)
      {:error, _reason} -> best_effort_string_fields(profile_context, route_key)
    end
  end

  @spec storage_key(String.t(), t()) :: {String.t(), String.t(), pos_integer(), String.t()}
  def storage_key(run_id, %__MODULE__{} = route_ref) when is_binary(run_id) do
    {run_id, route_ref.profile_kind, route_ref.profile_version, route_key_name(route_ref)}
  end

  @spec storage_key(String.t(), profile_context(), term()) ::
          {:ok, {String.t(), String.t(), pos_integer(), String.t()}} | {:error, term()}
  def storage_key(run_id, profile_context, route_key) when is_binary(run_id) do
    with {:ok, route_ref} <- new(profile_context, route_key) do
      {:ok, storage_key(run_id, route_ref)}
    end
  end

  def storage_key(run_id, _profile_context, _route_key), do: {:error, {:invalid_run_id, run_id}}

  defp resolve_profile(profile_context) do
    with {:ok, profile_kind} <- profile_kind(profile_context),
         {:ok, profile_version} <- profile_version(profile_context),
         {:ok, profile_module} <- ProfileRegistry.fetch(profile_kind, profile_version) do
      {:ok, {profile_kind, profile_version, profile_module}}
    end
  end

  defp normalize_route_key(route_key, profile_module, profile_kind, profile_version) do
    case RoutePolicy.normalize_route_key(route_key, profile_module) do
      normalized_route_key when is_atom(normalized_route_key) and not is_nil(normalized_route_key) ->
        {:ok, normalized_route_key}

      nil ->
        {:error, {:invalid_workflow_route_key, profile_kind, profile_version, route_key}}
    end
  end

  defp best_effort_event_fields(profile_context, route_key) do
    %{
      workflow_profile: profile_kind_value(profile_context),
      workflow_profile_version: profile_version_value(profile_context),
      workflow_route_key: route_key_name(route_key)
    }
  end

  defp best_effort_string_fields(profile_context, route_key) do
    %{
      "workflow_profile" => profile_kind_value(profile_context),
      "workflow_profile_version" => profile_version_value(profile_context),
      "workflow_route_key" => route_key_name(route_key)
    }
  end

  defp profile_kind(profile_context) do
    case profile_context |> field(:kind) |> normalize_kind() do
      nil -> {:error, {:invalid_workflow_profile_kind, field(profile_context, :kind)}}
      profile_kind -> {:ok, profile_kind}
    end
  end

  defp profile_kind_value(profile_context) do
    case profile_kind(profile_context) do
      {:ok, profile_kind} -> profile_kind
      {:error, _reason} -> nil
    end
  end

  defp profile_version(profile_context) do
    case profile_context |> field(:version) |> normalize_version() do
      nil -> {:error, {:invalid_workflow_profile_version, field(profile_context, :version)}}
      profile_version -> {:ok, profile_version}
    end
  end

  defp profile_version_value(profile_context) do
    case profile_version(profile_context) do
      {:ok, profile_version} -> profile_version
      {:error, _reason} -> nil
    end
  end

  defp field(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp field(_map, _key), do: nil

  defp normalize_kind(kind) when is_binary(kind) do
    case String.trim(kind) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_kind(_kind), do: nil

  defp normalize_version(version) when is_integer(version) and version > 0, do: version

  defp normalize_version(version) when is_binary(version) do
    with {parsed, ""} <- version |> String.trim() |> Integer.parse(),
         true <- parsed > 0 do
      parsed
    else
      _invalid -> nil
    end
  end

  defp normalize_version(_version), do: nil

  defp route_key_name(%__MODULE__{route_key: route_key}), do: Atom.to_string(route_key)
  defp route_key_name(route_key) when is_atom(route_key), do: Atom.to_string(route_key)

  defp route_key_name(route_key) when is_binary(route_key) do
    case String.trim(route_key) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp route_key_name(_route_key), do: nil
end
