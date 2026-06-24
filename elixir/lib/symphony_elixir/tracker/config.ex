defmodule SymphonyElixir.Tracker.Config do
  @moduledoc """
  Typed configuration struct for the tracker subsystem.

  The five top-level fields form the **public contract** between the
  configuration layer and all adapter implementations:

    * `kind` — adapter identifier (e.g. `"linear"`, `"tapd"`, `"memory"`)
    * `endpoint` — base URL for the tracker API
    * `auth` — credentials map (`api_key`, `api_secret`, …)
    * `lifecycle` — state definitions (`active_states`, `terminal_states`,
      `state_phase_map`, `raw_state_by_route_key`, `policy_by_route_key`, `workflows_by_type`)
    * `provider` — opaque bag for adapter-specific settings; the core layer
      never inspects this — only the owning adapter reads its contents

  ## Access Patterns

  Use the provided accessor functions (`kind/1`, `auth/1`, `provider/1`, …)
  rather than direct struct access, as they handle both atom and string keys
  gracefully during the config normalization transition.
  """

  alias SymphonyElixir.Config, as: RuntimeConfig

  defstruct [:kind, :endpoint, auth: %{}, lifecycle: %{}, provider: %{}]

  @type t :: %__MODULE__{
          kind: String.t() | nil,
          endpoint: String.t() | nil,
          auth: map(),
          lifecycle: map(),
          provider: map()
        }

  @spec current() :: {:ok, t()} | {:error, term()}
  def current do
    with {:ok, settings} <- RuntimeConfig.settings() do
      {:ok, to_config(settings.tracker)}
    end
  end

  @spec current!() :: t()
  def current! do
    RuntimeConfig.settings!().tracker
    |> to_config()
  end

  @spec kind(t()) :: String.t() | nil
  def kind(tracker), do: field(tracker, :kind)

  @spec endpoint(t()) :: String.t() | nil
  def endpoint(tracker), do: field(tracker, :endpoint)

  @spec auth(t()) :: map()
  def auth(tracker), do: field(tracker, :auth) |> map_value()

  @spec provider(t()) :: map()
  def provider(tracker), do: field(tracker, :provider) |> map_value()

  @spec lifecycle(t()) :: map()
  def lifecycle(tracker), do: field(tracker, :lifecycle) |> map_value()

  @spec api_key(t()) :: String.t() | nil
  def api_key(tracker), do: nested_value(auth(tracker), "api_key")

  @spec api_secret(t()) :: String.t() | nil
  def api_secret(tracker), do: nested_value(auth(tracker), "api_secret")

  @spec active_states(t()) :: [String.t()] | nil
  def active_states(tracker), do: lifecycle(tracker) |> nested_value("active_states") |> optional_list_value()

  @spec terminal_states(t()) :: [String.t()] | nil
  def terminal_states(tracker), do: lifecycle(tracker) |> nested_value("terminal_states") |> optional_list_value()

  @spec state_phase_map(t()) :: map() | nil
  def state_phase_map(tracker), do: lifecycle(tracker) |> nested_value("state_phase_map") |> optional_map_value()

  @spec raw_state_by_route_key(t()) :: map() | nil
  def raw_state_by_route_key(tracker), do: lifecycle(tracker) |> nested_value("raw_state_by_route_key") |> optional_map_value()

  @spec policy_by_route_key(t()) :: map() | nil
  def policy_by_route_key(tracker), do: lifecycle(tracker) |> nested_value("policy_by_route_key") |> optional_map_value()

  @spec workflows_by_type(t()) :: map() | nil
  def workflows_by_type(tracker), do: lifecycle(tracker) |> nested_value("workflows_by_type") |> optional_map_value()

  @spec workflow_raw_state_by_route_key(map()) :: map() | nil
  def workflow_raw_state_by_route_key(workflow) when is_map(workflow) do
    workflow
    |> nested_value("raw_state_by_route_key")
    |> optional_map_value()
  end

  def workflow_raw_state_by_route_key(_workflow), do: nil

  defp field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp field(_map, _key), do: nil

  defp to_config(%__MODULE__{} = tracker), do: tracker

  defp to_config(tracker) when is_map(tracker) do
    %__MODULE__{
      kind: field(tracker, :kind),
      endpoint: field(tracker, :endpoint),
      auth: tracker |> field(:auth) |> map_value(),
      provider: tracker |> field(:provider) |> map_value(),
      lifecycle: tracker |> field(:lifecycle) |> map_value()
    }
  end

  defp map_value(value) when is_map(value), do: value
  defp map_value(_value), do: %{}

  defp optional_list_value(nil), do: nil
  defp optional_list_value(value), do: List.wrap(value)

  defp optional_map_value(value) when is_map(value), do: value
  defp optional_map_value(nil), do: nil
  defp optional_map_value(_value), do: nil

  defp nested_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp nested_value(_map, _key), do: nil

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end
end
