defmodule SymphonyElixirWeb.Observability.Paths do
  @moduledoc false

  @base_path "/api/v1"

  @spec base_path() :: String.t()
  def base_path, do: @base_path

  @spec source_path() :: String.t()
  def source_path, do: @base_path <> "/source"

  @spec state_path() :: String.t()
  def state_path, do: @base_path <> "/state"

  @spec refresh_path() :: String.t()
  def refresh_path, do: @base_path <> "/refresh"

  @spec issue_route_path() :: String.t()
  def issue_route_path, do: @base_path <> "/:issue_identifier"

  @spec issue_path(String.t()) :: String.t()
  def issue_path(issue_identifier) when is_binary(issue_identifier) do
    @base_path <> "/" <> URI.encode(issue_identifier, &URI.char_unreserved?/1)
  end
end
