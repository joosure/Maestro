defmodule SymphonyElixir.Workflow.Template.PathRules do
  @moduledoc """
  Internal path and alias rules for workflow template assets.

  This module centralizes stable template path vocabulary such as the Markdown
  extension, reserved relative path segments, and partial directory name. Public
  callers should use `Workflow.Template`; registry, resolver, and asset-root
  internals use these rules to avoid local drift.
  """

  @markdown_extension ".md"
  @partials_dir "_partials"
  @platform_asset_dir "workflow_templates"
  @forbidden_relative_segments [".", ".."]
  @documentation_basename_pattern ~r/^README(?:\.[A-Za-z0-9_-]+)*\.md$/

  @spec markdown_extension() :: String.t()
  def markdown_extension, do: @markdown_extension

  @spec partials_dir() :: String.t()
  def partials_dir, do: @partials_dir

  @spec platform_asset_dir() :: String.t()
  def platform_asset_dir, do: @platform_asset_dir

  @spec forbidden_relative_segments() :: [String.t()]
  def forbidden_relative_segments, do: @forbidden_relative_segments

  @spec strip_markdown_extension(String.t()) :: String.t()
  def strip_markdown_extension(path) when is_binary(path),
    do: String.replace_suffix(path, @markdown_extension, "")

  @spec ensure_markdown_extension(String.t()) :: String.t()
  def ensure_markdown_extension(path) when is_binary(path) do
    if String.ends_with?(path, @markdown_extension),
      do: path,
      else: path <> @markdown_extension
  end

  @spec markdown_path?(Path.t()) :: boolean()
  def markdown_path?(path) when is_binary(path), do: Path.extname(path) == @markdown_extension

  @spec contains_forbidden_relative_segment?([String.t()]) :: boolean()
  def contains_forbidden_relative_segment?(segments) when is_list(segments),
    do: Enum.any?(segments, &forbidden_relative_segment?/1)

  @spec forbidden_relative_segment?(String.t()) :: boolean()
  def forbidden_relative_segment?(segment) when is_binary(segment),
    do: segment in @forbidden_relative_segments

  @spec documentation_basename?(String.t()) :: boolean()
  def documentation_basename?(basename) when is_binary(basename),
    do: Regex.match?(@documentation_basename_pattern, basename)
end
