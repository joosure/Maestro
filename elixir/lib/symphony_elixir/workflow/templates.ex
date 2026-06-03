defmodule SymphonyElixir.Workflow.Templates do
  @moduledoc false

  alias SymphonyElixir.Workflow.TemplateRegistry

  @template_dir "workflow_templates"

  @spec local_quickstart_alias() :: String.t()
  def local_quickstart_alias, do: TemplateRegistry.local_quickstart_alias()

  @spec root() :: Path.t()
  def root do
    [source_root(), code_priv_root()]
    |> Enum.reject(&is_nil/1)
    |> Enum.find(&File.dir?/1)
    |> case do
      nil -> source_root()
      path -> path
    end
  end

  @spec paths() :: [Path.t()]
  def paths do
    root()
    |> Path.join("**/*.md")
    |> Path.wildcard()
    |> Enum.reject(&(documentation_path?(&1) or partial_path?(&1)))
    |> Enum.sort()
  end

  @spec aliases() :: [String.t()]
  def aliases do
    Enum.map(paths(), &alias_for_path/1)
  end

  @spec resolve(String.t()) :: {:ok, Path.t()} | {:error, String.t()}
  def resolve(template_alias) when is_binary(template_alias) do
    with {:ok, relative_path} <- relative_template_path(template_alias) do
      template_path = Path.expand(Path.join(root(), relative_path))

      if File.regular?(template_path) do
        {:ok, template_path}
      else
        {:error, "Workflow template not found: #{String.trim(template_alias)} (#{template_path})"}
      end
    end
  end

  defp relative_template_path(template_alias) do
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
    end
  end

  defp ensure_markdown_extension(template_alias) do
    if String.ends_with?(template_alias, ".md"),
      do: template_alias,
      else: template_alias <> ".md"
  end

  defp validate_template_segments(relative_path) do
    segments = Path.split(relative_path)

    cond do
      Enum.any?(segments, &(&1 in [".", ".."])) ->
        {:error, "Workflow template alias must stay under #{root()}"}

      Path.extname(relative_path) != ".md" ->
        {:error, "Workflow template alias must resolve to a .md file"}

      documentation_basename?(List.last(segments)) ->
        {:error, "Workflow template alias must point to a workflow template"}

      true ->
        {:ok, Path.join(segments)}
    end
  end

  defp alias_for_path(path) do
    path
    |> Path.relative_to(root())
    |> Path.rootname()
  end

  defp documentation_path?(path) do
    path
    |> Path.basename()
    |> documentation_basename?()
  end

  defp documentation_basename?(basename) do
    Regex.match?(~r/^README(?:\.[A-Za-z0-9_-]+)*\.md$/, basename)
  end

  defp partial_path?(path) do
    path
    |> Path.relative_to(root())
    |> Path.split()
    |> List.first()
    |> Kernel.==("_partials")
  end

  defp source_root do
    __ENV__.file
    |> Path.dirname()
    |> Path.join("../../../priv/#{@template_dir}")
    |> Path.expand()
  end

  defp code_priv_root do
    case :code.priv_dir(:symphony_elixir) do
      path when is_list(path) -> Path.join(to_string(path), @template_dir)
      _other -> nil
    end
  end
end
