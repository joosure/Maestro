defmodule SymphonyElixirWeb.Observability.Status do
  @moduledoc false

  alias SymphonyElixir.Orchestrator.Retry.Status, as: RetryStatus

  @running "running"
  @retrying "retrying"
  @retry_scheduled RetryStatus.retry_scheduled()
  @unknown "unknown"

  @active_markers ["progress", @running, "active"]
  @danger_markers ["blocked", "error", "failed"]
  @warning_markers ["todo", "queued", "pending", "retry"]

  @spec running() :: String.t()
  def running, do: @running

  @spec retrying() :: String.t()
  def retrying, do: @retrying

  @spec retry_scheduled() :: String.t()
  def retry_scheduled, do: @retry_scheduled

  @spec unknown() :: String.t()
  def unknown, do: @unknown

  @spec badge_class(term(), String.t()) :: String.t()
  def badge_class(state, base \\ "state-badge") when is_binary(base) do
    normalized = state |> to_string() |> String.downcase()

    cond do
      String.contains?(normalized, @active_markers) -> "#{base} state-badge-active"
      String.contains?(normalized, @danger_markers) -> "#{base} state-badge-danger"
      String.contains?(normalized, @warning_markers) -> "#{base} state-badge-warning"
      true -> base
    end
  end
end
