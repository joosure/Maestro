defmodule SymphonyElixir.AgentProvider.AppServer.Messages do
  @moduledoc false

  require Logger

  alias SymphonyElixir.AgentProvider.Kinds

  @claude_code_kind Kinds.claude_code()
  @opencode_kind Kinds.opencode()

  @type event_name :: atom() | String.t()

  @spec emit((map() -> term()), event_name(), map(), map(), keyword()) :: :ok
  def emit(on_message, event, payload, metadata, opts \\ [])
      when is_function(on_message, 1) and is_map(payload) and is_map(metadata) and is_list(opts) do
    message =
      metadata
      |> Map.merge(%{event: event, timestamp: DateTime.utc_now()})
      |> Map.merge(payload)

    on_message.(message)
    :ok
  rescue
    error ->
      Logger.debug("#{provider_label(opts, metadata)} on_message callback failed: #{Exception.message(error)}")
      :ok
  end

  @spec issue_title(map() | nil) :: String.t()
  def issue_title(%{identifier: identifier, title: title}) when is_binary(identifier) and is_binary(title),
    do: "#{identifier}: #{title}"

  def issue_title(%{title: title}) when is_binary(title), do: title
  def issue_title(_issue), do: "agent turn"

  defp provider_label(opts, metadata) when is_list(opts) and is_map(metadata) do
    case Keyword.get(opts, :provider_label) do
      label when is_binary(label) and label != "" -> label
      _label -> metadata |> provider_kind() |> provider_label_from_kind()
    end
  end

  defp provider_kind(metadata) when is_map(metadata) do
    Map.get(metadata, :agent_provider_kind) || Map.get(metadata, "agent_provider_kind")
  end

  defp provider_label_from_kind(@claude_code_kind), do: "Claude Code"
  defp provider_label_from_kind(@opencode_kind), do: "OpenCode"
  defp provider_label_from_kind(kind) when is_binary(kind) and kind != "", do: kind
  defp provider_label_from_kind(_kind), do: "Agent provider"
end
