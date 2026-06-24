defmodule SymphonyElixir.Workflow.Template.Resolver do
  @moduledoc """
  Resolver implementation for registered workflow template assets.

  This module owns alias validation, template path resolution, and partial-root
  checks. It consumes `Workflow.Template.Registry` entries and does not own
  concrete workflow-extension template metadata.
  """

  alias SymphonyElixir.Workflow.Template.PathRules
  alias SymphonyElixir.Workflow.Template.Registry, as: TemplateRegistry

  @spec local_quickstart_alias() :: String.t()
  def local_quickstart_alias, do: TemplateRegistry.local_quickstart_alias()

  @spec root() :: Path.t()
  def root, do: TemplateRegistry.platform_asset_root()

  @spec roots() :: [Path.t()]
  def roots do
    TemplateRegistry.entries()
    |> Enum.map(&Path.expand(&1.asset_root))
    |> Enum.uniq()
  end

  @spec root_for(Path.t()) :: Path.t()
  def root_for(path) when is_binary(path) do
    expanded_path = Path.expand(path)

    Enum.find(roots(), fn root ->
      expanded_root = Path.expand(root)
      expanded_path == expanded_root or String.starts_with?(expanded_path, expanded_root <> "/")
    end) || root()
  end

  @spec paths() :: [Path.t()]
  def paths do
    TemplateRegistry.entries()
    |> Enum.map(& &1.asset_path)
    |> Enum.sort()
  end

  @spec aliases() :: [String.t()]
  def aliases, do: TemplateRegistry.aliases()

  @spec partial_roots() :: [Path.t()]
  def partial_roots do
    roots()
    |> Enum.map(&(Path.join(&1, PathRules.partials_dir()) |> Path.expand()))
  end

  @spec partial_allowed?(Path.t()) :: boolean()
  def partial_allowed?(path) when is_binary(path) do
    expanded_path = Path.expand(path)

    Enum.any?(partial_roots(), fn partial_root ->
      expanded_root = Path.expand(partial_root)
      expanded_path == expanded_root or String.starts_with?(expanded_path, expanded_root <> "/")
    end)
  end

  @spec resolve(String.t()) :: {:ok, Path.t()} | {:error, String.t()}
  def resolve(template_alias) when is_binary(template_alias) do
    with {:ok, normalized_alias} <- normalize_template_alias(template_alias),
         {:ok, entry} <- fetch_entry(normalized_alias) do
      template_path = Path.expand(entry.asset_path)

      if File.regular?(template_path),
        do: {:ok, template_path},
        else: {:error, "Workflow template not found: #{String.trim(template_alias)} (#{template_path})"}
    end
  end

  defp normalize_template_alias(template_alias) do
    template_alias = String.trim(template_alias)

    cond do
      template_alias == "" ->
        {:error, "Workflow template alias is required"}

      String.contains?(template_alias, "\\") ->
        {:error, "Workflow template alias must use forward-slash path segments"}

      Path.type(template_alias) == :absolute ->
        {:error, "Workflow template alias must be relative to #{root()}"}

      true ->
        template_alias
        |> ensure_markdown_extension()
        |> validate_template_segments()
        |> case do
          {:ok, relative_path} -> {:ok, Path.rootname(relative_path)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp ensure_markdown_extension(template_alias), do: PathRules.ensure_markdown_extension(template_alias)

  defp validate_template_segments(relative_path) do
    segments = Path.split(relative_path)

    cond do
      PathRules.contains_forbidden_relative_segment?(segments) ->
        {:error, "Workflow template alias must stay under #{root()}"}

      not PathRules.markdown_path?(relative_path) ->
        {:error, "Workflow template alias must resolve to a .md file"}

      PathRules.documentation_basename?(List.last(segments)) ->
        {:error, "Workflow template alias must point to a workflow template"}

      true ->
        {:ok, Path.join(segments)}
    end
  end

  defp fetch_entry(normalized_alias) do
    case TemplateRegistry.fetch(normalized_alias) do
      {:ok, entry} ->
        {:ok, entry}

      :error ->
        template_path = TemplateRegistry.asset_path!(root(), normalized_alias)
        {:error, "Workflow template not found: #{normalized_alias} (#{template_path})"}
    end
  end
end
