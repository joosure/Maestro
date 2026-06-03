defmodule SymphonyElixir.RepoProvider.CheckRun do
  @moduledoc """
  Internal normalized check-run contract shared by repo providers.

  GitHub and CNB normalizers both emit this shape after adapting external API
  state. Consumers should depend on this module instead of duplicating check
  status and conclusion literals.
  """

  @unknown "unknown"
  @status_completed "completed"
  @conclusion_pending "pending"
  @conclusion_success "success"
  @conclusion_neutral "neutral"
  @conclusion_skipped "skipped"
  @successful_conclusions [@conclusion_success, @conclusion_neutral, @conclusion_skipped]

  @spec unknown() :: String.t()
  def unknown, do: @unknown

  @spec completed_status() :: String.t()
  def completed_status, do: @status_completed

  @spec pending_conclusion() :: String.t()
  def pending_conclusion, do: @conclusion_pending

  @spec successful_conclusions() :: [String.t()]
  def successful_conclusions, do: @successful_conclusions

  @spec field(map(), String.t()) :: term()
  def field(check, key) when is_map(check) and is_binary(key) do
    Map.get(check, key) || Map.get(check, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(check, key)
  end

  def field(_check, _key), do: nil

  @spec name(map()) :: String.t()
  def name(check), do: field(check, "name") || unknown()

  @spec status(map()) :: String.t() | nil
  def status(check), do: field(check, "status")

  @spec conclusion(map()) :: String.t() | nil
  def conclusion(check), do: field(check, "conclusion")

  @spec normalized_status(map()) :: String.t() | nil
  def normalized_status(check), do: normalize(status(check))

  @spec normalized_conclusion(map()) :: String.t() | nil
  def normalized_conclusion(check), do: normalize(conclusion(check))

  @spec display_status(map()) :: String.t()
  def display_status(check), do: status(check) || unknown()

  @spec display_conclusion(map()) :: String.t()
  def display_conclusion(check), do: conclusion(check) || pending_conclusion()

  @spec completed?(map()) :: boolean()
  def completed?(check), do: normalized_status(check) == completed_status()

  @spec successful_conclusion?(term()) :: boolean()
  def successful_conclusion?(conclusion), do: normalize(conclusion) in @successful_conclusions

  @spec successful_completed?(map()) :: boolean()
  def successful_completed?(check), do: completed?(check) and successful_conclusion?(conclusion(check))

  defp normalize(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize(value) when is_atom(value), do: value |> Atom.to_string() |> normalize()
  defp normalize(_value), do: nil
end
