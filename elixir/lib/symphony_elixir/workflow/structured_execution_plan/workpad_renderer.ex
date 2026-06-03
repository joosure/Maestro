defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.WorkpadRenderer do
  @moduledoc """
  Deterministic backend renderer for structured execution plan Workpads.

  Rendered Markdown is derived only from canonical plan fields. Tracker
  Workpad text can be inspected for render state, but it is never imported as
  authoritative plan data.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Schema

  @render_schema "workflow.execution_plan.workpad_render.v1"
  @default_heading "Structured Execution Plan Workpad"
  @fingerprint_placeholder "__pending__"
  @marker_prefix "symphony:structured_execution_plan:v1"
  @max_items 100
  @max_text_chars 160
  @criticality_sections [
    {"handoff_blocking", "Handoff Blocking"},
    {"profile_required", "Profile Required"},
    {"informational", "Informational"}
  ]
  @required_marker_keys ~w(schema plan_id plan_revision tracker_kind mode rendered_item_count fingerprint)
  @allowed_marker_keys @required_marker_keys ++ ~w(workpad_id extensions)
  @marker_keys ~w(schema plan_id plan_revision tracker_kind mode rendered_item_count fingerprint)

  @spec render(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def render(plan, opts \\ [])

  def render(plan, opts) when is_map(plan) and is_list(opts) do
    with {:ok, valid_plan} <- Schema.validate(plan),
         {:ok, mode} <- render_mode(Keyword.get(opts, :mode, "preview")),
         {:ok, max_items} <- max_items(Keyword.get(opts, :max_items, @max_items)),
         {:ok, heading} <- heading(Keyword.get(opts, :heading, @default_heading)) do
      do_render(valid_plan, mode, heading, max_items)
    else
      {:error, %{code: _code} = reason} -> {:error, reason}
      {:error, reason} -> {:error, rendering_failed(reason)}
    end
  end

  def render(_plan, _opts), do: {:error, rendering_failed("Plan record must be an object.")}

  @spec validate_marker(map(), map()) :: {:ok, map()} | {:error, map()}
  def validate_marker(marker, plan) when is_map(marker) and is_map(plan) do
    errors =
      []
      |> collect_unknown_marker_keys(marker)
      |> collect_required_marker_keys(marker)
      |> collect_marker_schema(marker)
      |> collect_string(marker, "plan_id")
      |> collect_positive_integer(marker, "plan_revision")
      |> collect_string(marker, "tracker_kind")
      |> collect_mode(marker)
      |> collect_non_negative_integer(marker, "rendered_item_count")
      |> collect_string(marker, "fingerprint")
      |> collect_optional_string(marker, "workpad_id")
      |> collect_extensions(marker)
      |> collect_plan_match(marker, plan)

    if errors == [] do
      {:ok, marker}
    else
      {:error,
       %{
         code: "rendering_failed",
         message: "Structured execution plan Workpad render marker is invalid.",
         errors: errors
       }}
    end
  end

  def validate_marker(_marker, _plan) do
    {:error,
     %{
       code: "rendering_failed",
       message: "Structured execution plan Workpad render marker must be an object."
     }}
  end

  defp do_render(plan, mode, heading, max_items) do
    items = Map.get(plan, "items", [])
    visible_items = Enum.take(items, max_items)

    pending_marker =
      marker(plan, mode, length(visible_items))
      |> Map.put("fingerprint", @fingerprint_placeholder)

    pending_body = body(plan, visible_items, heading, pending_marker, length(items) > max_items)
    fingerprint = fingerprint(pending_body)
    final_marker = Map.put(pending_marker, "fingerprint", fingerprint)
    final_body = body(plan, visible_items, heading, final_marker, length(items) > max_items)

    {:ok,
     %{
       "mode" => mode,
       "heading" => heading,
       "body" => final_body,
       "fingerprint" => fingerprint,
       "marker" => final_marker,
       "plan_id" => Map.fetch!(plan, "plan_id"),
       "plan_revision" => Map.fetch!(plan, "revision"),
       "item_count" => length(items),
       "rendered_item_count" => length(visible_items),
       "items_truncated" => length(items) > max_items
     }}
  end

  defp body(plan, visible_items, heading, marker, items_truncated?) do
    [
      "## #{heading}",
      marker_line(marker),
      "",
      metadata_lines(plan),
      "",
      section_lines(visible_items),
      truncated_line(items_truncated?)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp metadata_lines(plan) do
    [
      "Plan: `#{inline_code(Map.fetch!(plan, "plan_id"))}`",
      "Run: `#{inline_code(Map.fetch!(plan, "run_id"))}`",
      "Issue: `#{inline_code(Map.fetch!(plan, "issue_id"))}`",
      "Tracker: `#{inline_code(Map.fetch!(plan, "tracker_kind"))}`",
      "Route: `#{inline_code(Map.fetch!(plan, "route_key"))}`",
      "Status: `#{inline_code(Map.fetch!(plan, "status"))}`",
      "Revision: `#{Map.fetch!(plan, "revision")}`"
    ]
  end

  defp section_lines([]), do: ["", "_No structured execution plan items._", ""]

  defp section_lines(items) do
    @criticality_sections
    |> Enum.flat_map(fn {criticality, label} ->
      section_items = Enum.filter(items, &(Map.get(&1, "criticality") == criticality))

      case section_items do
        [] -> []
        values -> ["", "### #{label}", "" | Enum.map(values, &item_line/1)]
      end
    end)
  end

  defp item_line(item) do
    [
      "- ",
      checkbox(Map.get(item, "status")),
      " `",
      inline_code(Map.get(item, "item_id")),
      "` ",
      bounded_text(Map.get(item, "title")),
      " - status: `",
      inline_code(Map.get(item, "status")),
      "`, kind: `",
      inline_code(Map.get(item, "kind")),
      "`, owner: `",
      inline_code(Map.get(item, "owned_by")),
      "`, evidence: ",
      evidence_summary(Map.get(item, "evidence_refs", []))
    ]
    |> IO.iodata_to_binary()
  end

  defp checkbox(status) when status in ["complete", "skipped"], do: "[x]"
  defp checkbox(_status), do: "[ ]"

  defp evidence_summary([]), do: "none"

  defp evidence_summary(refs) when is_list(refs) do
    refs
    |> Enum.map(&Map.get(&1, "evidence_kind"))
    |> Enum.filter(&is_binary/1)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {kind, _count} -> kind end)
    |> Enum.map_join(", ", fn {kind, count} -> "#{bounded_text(kind)}:#{count}" end)
    |> case do
      "" -> "none"
      summary -> summary
    end
  end

  defp evidence_summary(_refs), do: "none"

  defp truncated_line(false), do: nil
  defp truncated_line(true), do: ["", "_Additional items were omitted from this bounded render._"]

  defp marker(plan, mode, rendered_item_count) do
    %{
      "schema" => @render_schema,
      "plan_id" => Map.fetch!(plan, "plan_id"),
      "plan_revision" => Map.fetch!(plan, "revision"),
      "tracker_kind" => Map.fetch!(plan, "tracker_kind"),
      "mode" => mode,
      "rendered_item_count" => rendered_item_count,
      "fingerprint" => @fingerprint_placeholder
    }
  end

  defp marker_line(marker) do
    encoded =
      @marker_keys
      |> Enum.map_join("&", fn key -> "#{key}=#{URI.encode_www_form(to_string(Map.fetch!(marker, key)))}" end)

    "<!-- #{@marker_prefix} #{encoded} -->"
  end

  defp render_mode("preview"), do: {:ok, "preview"}
  defp render_mode("write"), do: {:ok, "write"}
  defp render_mode(mode), do: {:error, {:invalid_arguments, "Unsupported structured plan Workpad render mode #{inspect(mode)}."}}

  defp heading(value) when is_binary(value) do
    case bounded_text(value) do
      "" -> {:error, {:invalid_arguments, "Workpad heading must be a non-empty string."}}
      heading -> {:ok, heading}
    end
  end

  defp heading(_value), do: {:error, {:invalid_arguments, "Workpad heading must be a non-empty string."}}

  defp max_items(value) when is_integer(value) and value > 0, do: {:ok, min(value, @max_items)}
  defp max_items(_value), do: {:error, {:invalid_arguments, "max_items must be a positive integer."}}

  defp fingerprint(body) do
    :sha256
    |> :crypto.hash(body)
    |> Base.url_encode64(padding: false)
    |> String.slice(0, 24)
  end

  defp inline_code(value) do
    value
    |> bounded_text()
    |> String.replace("`", "'")
  end

  defp bounded_text(value) when is_binary(value) do
    value
    |> String.replace(~r/[\r\n\t]+/, " ")
    |> String.trim()
    |> redact_secret_like_text()
    |> String.slice(0, @max_text_chars)
  end

  defp bounded_text(value) when is_integer(value), do: Integer.to_string(value)
  defp bounded_text(value) when is_boolean(value), do: to_string(value)
  defp bounded_text(_value), do: ""

  defp redact_secret_like_text(text) do
    text
    |> String.replace(~r/(?i)(api[_-]?key|token|secret|password|authorization)\s*[:=]\s*[^,\s\]\)]+/, "\\1=[redacted]")
    |> String.replace(~r/sk-[A-Za-z0-9_-]{12,}/, "[redacted]")
  end

  defp collect_unknown_marker_keys(errors, marker) do
    marker
    |> Map.keys()
    |> Enum.reject(&(&1 in @allowed_marker_keys))
    |> Enum.map(fn key -> %{code: "unknown_key", path: [key], message: "Unknown render marker key is not allowed."} end)
    |> then(&(errors ++ &1))
  end

  defp collect_required_marker_keys(errors, marker) do
    @required_marker_keys
    |> Enum.reject(&Map.has_key?(marker, &1))
    |> Enum.map(fn key -> %{code: "missing_required_field", path: [key], message: "Required render marker field is missing."} end)
    |> then(&(errors ++ &1))
  end

  defp collect_marker_schema(errors, %{"schema" => @render_schema}), do: errors

  defp collect_marker_schema(errors, marker) do
    if Map.has_key?(marker, "schema") do
      errors ++ [%{code: "invalid_schema", path: ["schema"], message: "Unsupported render marker schema."}]
    else
      errors
    end
  end

  defp collect_mode(errors, %{"mode" => mode}) when mode in ["preview", "write"], do: errors

  defp collect_mode(errors, marker) do
    if Map.has_key?(marker, "mode") do
      errors ++ [%{code: "invalid_enum", path: ["mode"], message: "Unsupported render mode."}]
    else
      errors
    end
  end

  defp collect_string(errors, marker, key) do
    if Map.has_key?(marker, key) and not non_empty_string?(Map.get(marker, key)) do
      errors ++ [%{code: "invalid_type", path: [key], message: "Field must be a non-empty string."}]
    else
      errors
    end
  end

  defp collect_optional_string(errors, marker, key) do
    if Map.has_key?(marker, key) and not non_empty_string?(Map.get(marker, key)) do
      errors ++ [%{code: "invalid_type", path: [key], message: "Optional field must be a non-empty string."}]
    else
      errors
    end
  end

  defp collect_positive_integer(errors, marker, key) do
    if Map.has_key?(marker, key) and not positive_integer?(Map.get(marker, key)) do
      errors ++ [%{code: "invalid_type", path: [key], message: "Field must be a positive integer."}]
    else
      errors
    end
  end

  defp collect_non_negative_integer(errors, marker, key) do
    if Map.has_key?(marker, key) and not non_negative_integer?(Map.get(marker, key)) do
      errors ++ [%{code: "invalid_type", path: [key], message: "Field must be a non-negative integer."}]
    else
      errors
    end
  end

  defp collect_extensions(errors, marker) do
    case Map.fetch(marker, "extensions") do
      :error ->
        errors

      {:ok, extensions} when is_map(extensions) ->
        extension_errors =
          extensions
          |> Map.keys()
          |> Enum.reject(&namespaced_key?/1)
          |> Enum.map(fn key ->
            %{code: "invalid_extension_key", path: ["extensions", key], message: "Extension keys must be namespaced."}
          end)

        errors ++ extension_errors

      {:ok, _extensions} ->
        errors ++ [%{code: "invalid_type", path: ["extensions"], message: "Extensions must be an object."}]
    end
  end

  defp collect_plan_match(errors, marker, plan) do
    errors
    |> maybe_add_plan_match_error(marker, plan, "plan_id", "plan_id")
    |> maybe_add_plan_match_error(marker, plan, "tracker_kind", "tracker_kind")
    |> maybe_add_plan_match_error(marker, plan, "plan_revision", "revision")
  end

  defp maybe_add_plan_match_error(errors, marker, plan, marker_key, plan_key) do
    if Map.has_key?(marker, marker_key) and Map.has_key?(plan, plan_key) and Map.get(marker, marker_key) != Map.get(plan, plan_key) do
      errors ++
        [
          %{
            code: "render_marker_mismatch",
            path: [marker_key],
            message: "Render marker does not match the structured execution plan."
          }
        ]
    else
      errors
    end
  end

  defp rendering_failed({:invalid_arguments, _message} = reason), do: reason

  defp rendering_failed(message) when is_binary(message) do
    %{code: "rendering_failed", message: message}
  end

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""
  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp non_negative_integer?(value), do: is_integer(value) and value >= 0
  defp namespaced_key?(value) when is_binary(value), do: String.contains?(value, ".")
  defp namespaced_key?(_value), do: false

  @spec render_schema() :: String.t()
  def render_schema, do: @render_schema

  @spec default_heading() :: String.t()
  def default_heading, do: @default_heading
end
