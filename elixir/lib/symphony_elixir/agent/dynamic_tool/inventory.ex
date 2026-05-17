defmodule SymphonyElixir.Agent.DynamicTool.Inventory do
  @moduledoc """
  Resolves typed workflow tool capabilities to concrete runtime tool names.

  Fallback policy is an operator migration mechanism for replacing a missing
  typed capability during rollout. It is not a routine workflow execution path
  and must not be used to reintroduce arbitrary raw provider passthrough.
  """

  alias SymphonyElixir.Agent.DynamicTool.{Context, MetadataContract}
  alias SymphonyElixir.Workflow.CapabilityNames

  @typed_capabilities MapSet.new(CapabilityNames.typed_workflow())
  @workflow_capability_key MetadataContract.workflow_capability()
  @side_effect_key MetadataContract.side_effect()
  @source_kind_key MetadataContract.source_kind()
  @schema_version_key MetadataContract.schema_version()
  @deprecated_key MetadataContract.deprecated()
  @default_side_effect MetadataContract.default_side_effect()
  @default_schema_version MetadataContract.default_schema_version()

  @type resolved_tool :: %{
          required(:capability) => String.t(),
          required(:tool) => String.t(),
          required(:side_effect) => String.t(),
          required(:source_kind) => String.t() | nil,
          required(:schema_version) => String.t(),
          required(:deprecated?) => boolean(),
          required(:fallback?) => boolean(),
          optional(:fallback_reason) => String.t()
        }

  @type fallback_policy :: %{optional(String.t()) => String.t() | map()}

  @spec typed_tools(map()) :: [resolved_tool()]
  def typed_tools(tool_context) when is_map(tool_context) do
    metadata = Map.get(tool_context, :tool_metadata) || Map.get(tool_context, "tool_metadata") || %{}

    tool_context
    |> Context.tool_specs()
    |> Enum.flat_map(&typed_tool_from_spec(&1, metadata))
  end

  def typed_tools(_tool_context), do: []

  @spec resolve_required(map(), [String.t()], keyword()) :: {:ok, [resolved_tool()]} | {:error, term()}
  def resolve_required(tool_context, capabilities, opts \\ [])

  def resolve_required(tool_context, capabilities, opts)
      when is_map(tool_context) and is_list(capabilities) and is_list(opts) do
    typed_capabilities = Enum.filter(capabilities, &typed_capability?/1)
    typed_tools = typed_tools(tool_context)
    fallback_policy = Keyword.get(opts, :fallback_policy, %{}) |> normalize_fallback_policy()

    Enum.reduce_while(typed_capabilities, {:ok, []}, fn capability, {:ok, resolved} ->
      case resolve_capability(typed_tools, capability) do
        {:ok, tool} ->
          {:cont, {:ok, [tool | resolved]}}

        {:error, {:missing_typed_workflow_tool, ^capability}} ->
          case resolve_fallback(tool_context, fallback_policy, capability) do
            {:ok, tool} -> {:cont, {:ok, [tool | resolved]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      {:error, _reason} = error -> error
    end
  end

  @spec render(map(), keyword()) :: String.t()
  def render(tool_context, opts \\ [])

  def render(tool_context, opts) when is_map(tool_context) and is_list(opts) do
    fallback_policy = Keyword.get(opts, :fallback_policy, %{}) |> normalize_fallback_policy()

    case inventory_tools(tool_context, fallback_policy) do
      [] ->
        """
        ## Typed Workflow Tool Inventory

        No typed workflow tools are advertised for this session. Use provider
        skills and documented operator migration fallback tools only when the
        workflow explicitly permits that migration policy.
        """
        |> String.trim()

      tools ->
        rows =
          tools
          |> Enum.sort_by(&{&1.capability, &1.tool})
          |> Enum.map_join("\n", &inventory_row(&1, opts))

        case rows do
          "" ->
            """
            ## Typed Workflow Tool Inventory

            No non-deprecated typed workflow tools are advertised for this
            session. Use provider skills and documented operator migration
            fallback tools only when the workflow explicitly permits that
            migration policy.
            """
            |> String.trim()

          rows ->
            rendered_inventory(rows, opts)
        end
    end
  end

  def render(_tool_context, _opts), do: render(%{tool_specs: [], tool_metadata: %{}})

  @spec typed_capability?(term()) :: boolean()
  def typed_capability?(capability) when is_binary(capability) do
    MapSet.member?(@typed_capabilities, capability)
  end

  def typed_capability?(_capability), do: false

  defp typed_tool_from_spec(%{"name" => name}, metadata) when is_binary(name) and is_map(metadata) do
    case Map.get(metadata, name, %{}) do
      tool_metadata when is_map(tool_metadata) ->
        capability = string_field(tool_metadata, @workflow_capability_key)

        if is_binary(capability) do
          [
            %{
              capability: capability,
              tool: name,
              side_effect: string_field(tool_metadata, @side_effect_key) || @default_side_effect,
              source_kind: string_field(tool_metadata, @source_kind_key),
              schema_version: string_field(tool_metadata, @schema_version_key) || @default_schema_version,
              deprecated?: Map.get(tool_metadata, @deprecated_key, false) == true,
              fallback?: false
            }
          ]
        else
          []
        end

      _metadata ->
        []
    end
  end

  defp typed_tool_from_spec(_tool_spec, _metadata), do: []

  defp resolve_capability(tools, capability) do
    matches =
      tools
      |> Enum.filter(&(&1.capability == capability))
      |> Enum.reject(& &1.deprecated?)

    case matches do
      [tool] -> {:ok, tool}
      [] -> {:error, {:missing_typed_workflow_tool, capability}}
      matches -> {:error, {:ambiguous_typed_workflow_tool, capability, Enum.map(matches, & &1.tool)}}
    end
  end

  defp resolve_fallback(tool_context, fallback_policy, capability) do
    case Map.get(fallback_policy, capability) do
      %{tool: tool} = fallback ->
        fallback_tool(tool_context, capability, tool, fallback)

      _fallback ->
        {:error, {:missing_typed_workflow_tool, capability}}
    end
  end

  defp fallback_tool(tool_context, capability, tool, fallback) do
    with %{"name" => ^tool} <- Context.tool_spec(tool_context, tool),
         metadata <- metadata_for(tool_context, tool),
         :ok <- validate_fallback_metadata(metadata, capability, tool) do
      {:ok,
       %{
         capability: capability,
         tool: tool,
         side_effect: string_field(metadata, @side_effect_key) || @default_side_effect,
         source_kind: string_field(metadata, @source_kind_key),
         schema_version: string_field(metadata, @schema_version_key) || @default_schema_version,
         deprecated?: false,
         fallback?: true,
         fallback_reason: Map.get(fallback, :reason)
       }}
    else
      nil -> {:error, {:missing_fallback_workflow_tool, capability, tool}}
      {:error, reason} -> {:error, reason}
      _spec -> {:error, {:missing_fallback_workflow_tool, capability, tool}}
    end
  end

  defp validate_fallback_metadata(metadata, capability, tool) when is_map(metadata) do
    cond do
      Map.get(metadata, @deprecated_key, false) == true ->
        {:error, {:deprecated_fallback_workflow_tool, capability, tool}}

      is_binary(string_field(metadata, @workflow_capability_key)) ->
        {:error, {:typed_fallback_workflow_tool, capability, tool, string_field(metadata, @workflow_capability_key)}}

      true ->
        :ok
    end
  end

  defp inventory_tools(tool_context, fallback_policy) do
    tools = typed_tools(tool_context)

    typed_rows =
      Enum.reject(tools, & &1.deprecated?)

    typed_capabilities = MapSet.new(typed_rows, & &1.capability)

    fallback_rows =
      fallback_policy
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(typed_capabilities, &1))
      |> Enum.flat_map(fn capability ->
        case resolve_fallback(tool_context, fallback_policy, capability) do
          {:ok, tool} -> [tool]
          {:error, _reason} -> []
        end
      end)

    typed_rows ++ fallback_rows
  end

  defp rendered_inventory(rows, opts) do
    case provider_callable_name(opts) do
      {:ok, _callable_name} ->
        provider_note = provider_callable_note(opts)
        provider_label = provider_callable_label(opts)

        """
        ## Typed Workflow Tool Inventory

        Use these exact provider-facing callable tool names for routine workflow
        actions. #{provider_note} Do not guess provider API fields, mutation
        names, CLI arguments, or alternate tool names for these capabilities.
        If a listed typed tool returns a validation or provider error, correct
        the typed tool arguments and retry that same typed tool. Do not switch to
        raw provider tools, helper CLIs, shell commands, or alternate tool names
        unless this inventory marks an explicit operator migration fallback for
        the capability.

        | Capability | #{provider_label} | Runtime tool | Side effect | Source | Migration fallback |
        | --- | --- | --- | --- | --- | --- |
        #{rows}
        """
        |> String.trim()

      :error ->
        """
        ## Typed Workflow Tool Inventory

        Use these exact runtime tool names for routine workflow actions.
        Do not guess provider API fields, mutation names, CLI arguments, or
        alternate tool names for these capabilities.
        If a listed typed tool returns a validation or provider error, correct
        the typed tool arguments and retry that same typed tool. Do not switch to
        raw provider tools, helper CLIs, shell commands, or alternate tool names
        unless this inventory marks an explicit operator migration fallback for
        the capability.

        | Capability | Runtime tool | Side effect | Source | Migration fallback |
        | --- | --- | --- | --- | --- |
        #{rows}
        """
        |> String.trim()
    end
  end

  defp inventory_row(tool, opts) do
    fallback =
      cond do
        tool.fallback? ->
          fallback_reason = Map.get(tool, :fallback_reason)

          if is_binary(fallback_reason) and fallback_reason != "" do
            "explicit operator migration fallback permitted: #{fallback_reason}"
          else
            "explicit operator migration fallback permitted"
          end

        tool.deprecated? ->
          "deprecated"

        true ->
          "blocked for routine workflow; only explicit operator migration policy can permit a non-typed tool"
      end

    case provider_callable_name(opts) do
      {:ok, callable_name} ->
        "| `#{tool.capability}` | `#{callable_name.(tool.tool)}` | `#{tool.tool}` | `#{tool.side_effect}` | `#{tool.source_kind || ""}` | #{fallback} |"

      :error ->
        "| `#{tool.capability}` | `#{tool.tool}` | `#{tool.side_effect}` | `#{tool.source_kind || ""}` | #{fallback} |"
    end
  end

  defp provider_callable_name(opts) when is_list(opts) do
    case Keyword.get(opts, :provider_callable_name) do
      callable_name when is_function(callable_name, 1) -> {:ok, callable_name}
      _callable_name -> :error
    end
  end

  defp provider_callable_label(opts) when is_list(opts) do
    case Keyword.get(opts, :provider_callable_label) do
      label when is_binary(label) and label != "" -> label
      _label -> "Tool to call"
    end
  end

  defp provider_callable_note(opts) when is_list(opts) do
    case Keyword.get(opts, :provider_callable_note) do
      note when is_binary(note) and note != "" -> note
      _note -> "The provider adapter generated these callable names for the active session."
    end
  end

  defp normalize_fallback_policy(policy) when is_map(policy) do
    policy
    |> Enum.flat_map(fn {capability, fallback} ->
      with capability when is_binary(capability) and capability != "" <- normalize_string(capability),
           {:ok, fallback} <- normalize_fallback(fallback) do
        [{capability, fallback}]
      else
        _invalid -> []
      end
    end)
    |> Map.new()
  end

  defp normalize_fallback_policy(_policy), do: %{}

  defp normalize_fallback(tool) when is_binary(tool) do
    case normalize_string(tool) do
      tool when is_binary(tool) -> {:ok, %{tool: tool}}
      _tool -> :error
    end
  end

  defp normalize_fallback(fallback) when is_map(fallback) do
    case fallback |> string_field(MetadataContract.tool()) |> normalize_string() do
      tool when is_binary(tool) ->
        reason = fallback |> string_field(MetadataContract.reason()) |> normalize_string()
        {:ok, %{tool: tool, reason: reason}}

      _tool ->
        :error
    end
  end

  defp normalize_fallback(_fallback), do: :error

  defp metadata_for(tool_context, tool) do
    metadata = Map.get(tool_context, :tool_metadata) || Map.get(tool_context, "tool_metadata") || %{}
    Map.get(metadata, tool, %{})
  end

  defp string_field(map, field) when is_map(map) and is_binary(field) do
    MetadataContract.field_value(map, field)
  end

  defp string_field(_map, _field), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(_value), do: nil
end
