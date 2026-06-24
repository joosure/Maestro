defmodule SymphonyElixir.Workflow.Extension.Runtime.Command do
  @moduledoc """
  Typed commands emitted by workflow extensions for platform execution.

  Extensions describe the requested platform side effect. The platform runtime
  decides how to execute it, keeping extensions independent from concrete
  Orchestrator modules.
  """

  @allowed_types [:release_blocked_resource]
  @release_blocked_resource_payload_keys [:reason, :resource_id, :resource_kind]
  @missing_payload_type "missing"
  @tracker_issue_resource_kind "tracker_issue"

  alias SymphonyElixir.Workflow.Extension.Diagnostics

  @enforce_keys [:type, :payload]
  defstruct [:type, :payload]

  @type command_type :: :release_blocked_resource
  @type reason :: atom() | String.t()

  @type t :: %__MODULE__{
          type: command_type(),
          payload: map()
        }

  @type diagnostic :: %{
          command_type: atom() | String.t() | nil,
          payload_type: String.t(),
          known_payload_fields: [atom()]
        }

  @spec release_blocked_issue(String.t(), reason()) :: t()
  def release_blocked_issue(issue_id, reason)
      when is_binary(issue_id) and ((is_atom(reason) and not is_nil(reason)) or is_binary(reason)) do
    release_blocked_resource(@tracker_issue_resource_kind, issue_id, reason)
  end

  @doc """
  Returns the platform resource kind used for tracker issue runtime commands.
  """
  @spec tracker_issue_resource_kind() :: String.t()
  def tracker_issue_resource_kind, do: @tracker_issue_resource_kind

  @spec release_blocked_resource(String.t(), String.t(), reason()) :: t()
  def release_blocked_resource(resource_kind, resource_id, reason)
      when is_binary(resource_kind) and is_binary(resource_id) and
             ((is_atom(reason) and not is_nil(reason)) or is_binary(reason)) do
    %__MODULE__{
      type: :release_blocked_resource,
      payload: %{
        resource_kind: resource_kind,
        resource_id: resource_id,
        reason: reason
      }
    }
  end

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{type: :release_blocked_resource, payload: payload}) do
    valid_release_blocked_resource_payload?(payload)
  end

  def valid?(_command), do: false

  @spec diagnostic(term()) :: diagnostic()
  def diagnostic(%__MODULE__{type: type, payload: payload}) do
    %{
      command_type: diagnostic_command_type(type),
      payload_type: Diagnostics.type_name(payload),
      known_payload_fields: known_payload_fields(payload)
    }
  end

  def diagnostic(command) do
    %{
      command_type: diagnostic_command_type(command_type(command)),
      payload_type: payload_type(command),
      known_payload_fields: []
    }
  end

  @spec known_type?(term()) :: boolean()
  def known_type?(type), do: type in @allowed_types

  @spec valid_reason?(term()) :: boolean()
  def valid_reason?(reason), do: (is_atom(reason) and not is_nil(reason)) or is_binary(reason)

  @spec valid_release_blocked_resource_payload?(term()) :: boolean()
  def valid_release_blocked_resource_payload?(%{
        resource_kind: resource_kind,
        resource_id: resource_id,
        reason: reason
      })
      when is_binary(resource_kind) and is_binary(resource_id) do
    valid_reason?(reason)
  end

  def valid_release_blocked_resource_payload?(_payload), do: false

  defp command_type(%{type: type}), do: type
  defp command_type(_command), do: nil

  defp payload_type(%{payload: payload}), do: Diagnostics.type_name(payload)
  defp payload_type(_command), do: @missing_payload_type

  defp diagnostic_command_type(type) when is_atom(type), do: type
  defp diagnostic_command_type(type) when is_binary(type), do: String.slice(type, 0, 128)
  defp diagnostic_command_type(_type), do: nil

  defp known_payload_fields(payload) when is_map(payload) do
    payload
    |> Map.keys()
    |> Enum.filter(&(&1 in @release_blocked_resource_payload_keys))
    |> Enum.sort()
  end

  defp known_payload_fields(_payload), do: []
end
