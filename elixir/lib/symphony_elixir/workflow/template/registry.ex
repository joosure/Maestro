defmodule SymphonyElixir.Workflow.Template.Registry do
  @moduledoc """
  Registry for bundled workflow template contracts.

  Workflow template files are user-facing configuration artifacts. This module
  owns the code-side contract for bundled template aliases, their expected
  structured front-matter fields, and their registered asset references.

  This registry owns the workflow-platform template lookup mechanism. It may
  define platform-owned quickstart templates; concrete extension templates must
  enter through `Workflow.Extension.Contributions` or a future manifest
  projection, not through direct aliases here.
  """

  alias SymphonyElixir.AgentProvider.Kinds, as: AgentProviderKinds
  alias SymphonyElixir.RepoProvider.Kinds, as: RepoProviderKinds
  alias SymphonyElixir.Tracker.Kinds, as: TrackerKinds
  alias SymphonyElixir.Workflow.Extension.Contributions
  alias SymphonyElixir.Workflow.Profiles.Triage
  alias SymphonyElixir.Workflow.Template.Assets, as: TemplateAssets
  alias SymphonyElixir.Workflow.Template.Entry
  alias SymphonyElixir.Workflow.Template.PathRules

  @entry_fields [
    :template_alias,
    :asset_root,
    :asset_path,
    :profile_kind,
    :profile_version,
    :tracker_kind,
    :repo_provider_kind,
    :agent_provider_kind,
    :credential_ref
  ]

  @required_entry_fields @entry_fields -- [:asset_path, :credential_ref]

  @type t :: Entry.t()

  @local_quickstart_alias "memory/no_repo/mock"

  @spec local_quickstart_alias() :: String.t()
  def local_quickstart_alias, do: @local_quickstart_alias

  @spec entries() :: [t()]
  def entries do
    platform_entries = [
      triage_template(
        @local_quickstart_alias,
        TrackerKinds.memory(),
        RepoProviderKinds.memory(),
        AgentProviderKinds.mock()
      )
    ]

    platform_entries ++ extension_entries()
  end

  @spec aliases() :: [String.t()]
  def aliases, do: Enum.map(entries(), & &1.template_alias)

  @spec platform_asset_root() :: Path.t()
  def platform_asset_root, do: TemplateAssets.app_priv_root!(PathRules.platform_asset_dir())

  @spec entry!(keyword() | map()) :: Entry.t()
  def entry!(attrs) when is_list(attrs), do: attrs |> Map.new() |> entry!()

  def entry!(attrs) when is_map(attrs) do
    attrs = validate_entry_attrs!(attrs)
    template_alias = required_string!(attrs, :template_alias)
    asset_root = required_string!(attrs, :asset_root) |> Path.expand()
    asset_path = entry_asset_path!(attrs, asset_root, template_alias)

    %Entry{
      template_alias: normalize_alias(template_alias),
      asset_root: asset_root,
      asset_path: asset_path,
      profile_kind: required_string!(attrs, :profile_kind),
      profile_version: positive_integer!(attrs, :profile_version),
      tracker_kind: required_string!(attrs, :tracker_kind),
      repo_provider_kind: required_string!(attrs, :repo_provider_kind),
      agent_provider_kind: required_string!(attrs, :agent_provider_kind),
      credential_ref: optional_string!(attrs, :credential_ref)
    }
  end

  @spec asset_path!(Path.t(), String.t()) :: Path.t()
  def asset_path!(asset_root, template_alias) when is_binary(asset_root) and is_binary(template_alias) do
    template_alias
    |> normalize_alias()
    |> ensure_markdown_extension()
    |> validate_relative_asset_path!()
    |> then(&Path.expand(Path.join(asset_root, &1)))
  end

  @spec fetch(String.t()) :: {:ok, t()} | :error
  def fetch(template_alias) when is_binary(template_alias) do
    template_alias = normalize_alias(template_alias)

    case Enum.find(entries(), &(&1.template_alias == template_alias)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  @spec fetch_by(String.t(), String.t(), String.t()) :: {:ok, t()} | :error
  def fetch_by(tracker_kind, repo_provider_kind, agent_provider_kind)
      when is_binary(tracker_kind) and is_binary(repo_provider_kind) and is_binary(agent_provider_kind) do
    case Enum.find(entries(), &entry_matches?(&1, tracker_kind, repo_provider_kind, agent_provider_kind)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  @spec alias_for!(String.t(), String.t(), String.t()) :: String.t()
  def alias_for!(tracker_kind, repo_provider_kind, agent_provider_kind) do
    case fetch_by(tracker_kind, repo_provider_kind, agent_provider_kind) do
      {:ok, entry} ->
        entry.template_alias

      :error ->
        raise ArgumentError,
              "unknown bundled workflow template for tracker=#{inspect(tracker_kind)}, " <>
                "repo_provider=#{inspect(repo_provider_kind)}, agent_provider=#{inspect(agent_provider_kind)}"
    end
  end

  defp triage_template(template_alias, tracker_kind, repo_provider_kind, agent_provider_kind) do
    entry!(
      template_alias: template_alias,
      asset_root: platform_asset_root(),
      profile_kind: Triage.kind(),
      profile_version: Triage.version(),
      tracker_kind: tracker_kind,
      repo_provider_kind: repo_provider_kind,
      agent_provider_kind: agent_provider_kind
    )
  end

  defp extension_entries do
    :template_entries
    |> Contributions.list!()
    |> Enum.filter(&match?(%Entry{}, &1))
  end

  defp normalize_alias(template_alias) do
    template_alias
    |> String.trim()
    |> PathRules.strip_markdown_extension()
  end

  defp ensure_markdown_extension(template_alias), do: PathRules.ensure_markdown_extension(template_alias)

  defp validate_relative_asset_path!(relative_path) do
    segments = Path.split(relative_path)

    cond do
      Path.type(relative_path) == :absolute ->
        raise ArgumentError, "workflow template asset path must be relative"

      PathRules.contains_forbidden_relative_segment?(segments) ->
        raise ArgumentError, "workflow template asset path must stay under its asset root"

      not PathRules.markdown_path?(relative_path) ->
        raise ArgumentError, "workflow template asset path must resolve to a .md file"

      true ->
        Path.join(segments)
    end
  end

  defp validate_entry_attrs!(attrs) do
    attrs = Map.new(attrs)
    unknown_fields = Map.keys(attrs) -- @entry_fields
    missing_fields = Enum.reject(@required_entry_fields, &Map.has_key?(attrs, &1))

    cond do
      unknown_fields != [] ->
        raise ArgumentError, "workflow template entry contains unsupported field(s): #{inspect(unknown_fields)}"

      missing_fields != [] ->
        raise ArgumentError, "workflow template entry is missing required field(s): #{inspect(missing_fields)}"

      true ->
        attrs
    end
  end

  defp entry_asset_path!(attrs, asset_root, template_alias) do
    case Map.get(attrs, :asset_path) do
      nil -> asset_path!(asset_root, template_alias)
      asset_path when is_binary(asset_path) -> validate_entry_asset_path!(asset_root, asset_path)
      value -> raise ArgumentError, "workflow template entry asset_path must be a string, got #{inspect(value)}"
    end
  end

  defp validate_entry_asset_path!(asset_root, asset_path) do
    expanded_root = Path.expand(asset_root)
    expanded_path = Path.expand(asset_path)

    cond do
      Path.type(asset_path) != :absolute ->
        raise ArgumentError, "workflow template entry asset_path must be absolute"

      not under_root?(expanded_path, expanded_root) ->
        raise ArgumentError, "workflow template entry asset_path must stay under its asset root"

      not PathRules.markdown_path?(expanded_path) ->
        raise ArgumentError, "workflow template entry asset_path must resolve to a .md file"

      true ->
        expanded_path
    end
  end

  defp under_root?(path, root), do: path == root or String.starts_with?(path, root <> "/")

  defp required_string!(attrs, field) do
    case Map.fetch!(attrs, field) do
      value when is_binary(value) ->
        value = String.trim(value)

        if value == "",
          do: raise(ArgumentError, "workflow template entry #{field} must be non-empty"),
          else: value

      value ->
        raise ArgumentError, "workflow template entry #{field} must be a string, got #{inspect(value)}"
    end
  end

  defp optional_string!(attrs, field) do
    case Map.get(attrs, field) do
      nil ->
        nil

      value when is_binary(value) ->
        value = String.trim(value)

        if value == "",
          do: nil,
          else: value

      value ->
        raise ArgumentError, "workflow template entry #{field} must be a string when present, got #{inspect(value)}"
    end
  end

  defp positive_integer!(attrs, field) do
    case Map.fetch!(attrs, field) do
      value when is_integer(value) and value > 0 -> value
      value -> raise ArgumentError, "workflow template entry #{field} must be a positive integer, got #{inspect(value)}"
    end
  end

  defp entry_matches?(entry, tracker_kind, repo_provider_kind, agent_provider_kind) do
    entry.tracker_kind == tracker_kind and
      entry.repo_provider_kind == repo_provider_kind and
      entry.agent_provider_kind == agent_provider_kind
  end
end
