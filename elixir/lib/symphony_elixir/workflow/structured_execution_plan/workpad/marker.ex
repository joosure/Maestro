defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Marker do
  @moduledoc """
  Render-marker construction and validation for structured-plan Workpads.

  Markers identify a backend-rendered projection. They are validated against a
  canonical plan before being stored, but they never import Workpad Markdown as
  authoritative plan data.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.ErrorCodes

  @schema_key Fields.schema()
  @plan_id_key Fields.plan_id()
  @tracker_kind_key Fields.tracker_kind()
  @revision_key Fields.revision()
  @extensions_key Fields.extensions()
  @mode_key Contract.mode_key()
  @plan_revision_key Contract.plan_revision_key()
  @rendered_item_count_key Contract.rendered_item_count_key()
  @fingerprint_key Contract.fingerprint_key()
  @workpad_id_key Contract.workpad_id_key()
  @render_schema Contract.render_schema()
  @render_modes Contract.render_modes()

  @spec build(map(), String.t(), non_neg_integer()) :: map()
  def build(plan, mode, rendered_item_count) when is_map(plan) and is_binary(mode) and is_integer(rendered_item_count) do
    %{
      @schema_key => Contract.render_schema(),
      @plan_id_key => Map.fetch!(plan, @plan_id_key),
      @plan_revision_key => Map.fetch!(plan, @revision_key),
      @tracker_kind_key => Map.fetch!(plan, @tracker_kind_key),
      @mode_key => mode,
      @rendered_item_count_key => rendered_item_count,
      @fingerprint_key => Contract.fingerprint_placeholder()
    }
  end

  @spec put_fingerprint(map(), String.t()) :: map()
  def put_fingerprint(marker, fingerprint) when is_map(marker) and is_binary(fingerprint) do
    Map.put(marker, @fingerprint_key, fingerprint)
  end

  @spec put_workpad_id(map(), String.t()) :: map()
  def put_workpad_id(marker, workpad_id) when is_map(marker) and is_binary(workpad_id) do
    Map.put(marker, @workpad_id_key, workpad_id)
  end

  @spec line(map()) :: String.t()
  def line(marker) when is_map(marker) do
    encoded =
      Contract.marker_line_keys()
      |> Enum.map_join("&", fn key -> "#{key}=#{URI.encode_www_form(to_string(Map.fetch!(marker, key)))}" end)

    "<!-- #{Contract.marker_prefix()} #{encoded} -->"
  end

  @spec fingerprint(String.t()) :: String.t()
  def fingerprint(body) when is_binary(body) do
    :sha256
    |> :crypto.hash(body)
    |> Base.url_encode64(padding: false)
    |> String.slice(0, 24)
  end

  @spec validate(map(), map()) :: {:ok, map()} | {:error, map()}
  def validate(marker, plan) when is_map(marker) and is_map(plan) do
    errors =
      []
      |> collect_unknown_marker_keys(marker)
      |> collect_required_marker_keys(marker)
      |> collect_marker_schema(marker)
      |> collect_string(marker, @plan_id_key)
      |> collect_positive_integer(marker, @plan_revision_key)
      |> collect_string(marker, @tracker_kind_key)
      |> collect_mode(marker)
      |> collect_non_negative_integer(marker, @rendered_item_count_key)
      |> collect_string(marker, @fingerprint_key)
      |> collect_optional_string(marker, @workpad_id_key)
      |> collect_extensions(marker)
      |> collect_plan_match(marker, plan)

    if errors == [] do
      {:ok, marker}
    else
      {:error,
       %{
         code: ErrorCodes.rendering_failed(),
         message: "Structured execution plan Workpad render marker is invalid.",
         errors: errors
       }}
    end
  end

  def validate(_marker, _plan) do
    {:error,
     %{
       code: ErrorCodes.rendering_failed(),
       message: "Structured execution plan Workpad render marker must be an object."
     }}
  end

  defp collect_unknown_marker_keys(errors, marker) do
    marker
    |> Map.keys()
    |> Enum.reject(&(&1 in Contract.allowed_marker_keys()))
    |> Enum.map(fn key -> %{code: ErrorCodes.unknown_key(), path: [key], message: "Unknown render marker key is not allowed."} end)
    |> then(&(errors ++ &1))
  end

  defp collect_required_marker_keys(errors, marker) do
    Contract.required_marker_keys()
    |> Enum.reject(&Map.has_key?(marker, &1))
    |> Enum.map(fn key -> %{code: ErrorCodes.missing_required_field(), path: [key], message: "Required render marker field is missing."} end)
    |> then(&(errors ++ &1))
  end

  defp collect_marker_schema(errors, %{@schema_key => @render_schema}), do: errors

  defp collect_marker_schema(errors, marker) do
    if Map.has_key?(marker, @schema_key) do
      errors ++ [%{code: ErrorCodes.invalid_schema(), path: [@schema_key], message: "Unsupported render marker schema."}]
    else
      errors
    end
  end

  defp collect_mode(errors, %{@mode_key => mode}) when mode in @render_modes, do: errors

  defp collect_mode(errors, marker) do
    if Map.has_key?(marker, @mode_key) do
      errors ++ [%{code: ErrorCodes.invalid_enum(), path: [@mode_key], message: "Unsupported render mode."}]
    else
      errors
    end
  end

  defp collect_string(errors, marker, key) do
    if Map.has_key?(marker, key) and not non_empty_string?(Map.get(marker, key)) do
      errors ++ [%{code: ErrorCodes.invalid_type(), path: [key], message: "Field must be a non-empty string."}]
    else
      errors
    end
  end

  defp collect_optional_string(errors, marker, key) do
    if Map.has_key?(marker, key) and not non_empty_string?(Map.get(marker, key)) do
      errors ++ [%{code: ErrorCodes.invalid_type(), path: [key], message: "Optional field must be a non-empty string."}]
    else
      errors
    end
  end

  defp collect_positive_integer(errors, marker, key) do
    if Map.has_key?(marker, key) and not positive_integer?(Map.get(marker, key)) do
      errors ++ [%{code: ErrorCodes.invalid_type(), path: [key], message: "Field must be a positive integer."}]
    else
      errors
    end
  end

  defp collect_non_negative_integer(errors, marker, key) do
    if Map.has_key?(marker, key) and not non_negative_integer?(Map.get(marker, key)) do
      errors ++ [%{code: ErrorCodes.invalid_type(), path: [key], message: "Field must be a non-negative integer."}]
    else
      errors
    end
  end

  defp collect_extensions(errors, marker) do
    case Map.fetch(marker, @extensions_key) do
      :error ->
        errors

      {:ok, extensions} when is_map(extensions) ->
        extension_errors =
          extensions
          |> Map.keys()
          |> Enum.reject(&namespaced_key?/1)
          |> Enum.map(fn key ->
            %{code: ErrorCodes.invalid_extension_key(), path: [@extensions_key, key], message: "Extension keys must be namespaced."}
          end)

        errors ++ extension_errors

      {:ok, _extensions} ->
        errors ++ [%{code: ErrorCodes.invalid_type(), path: [@extensions_key], message: "Extensions must be an object."}]
    end
  end

  defp collect_plan_match(errors, marker, plan) do
    errors
    |> maybe_add_plan_match_error(marker, plan, @plan_id_key, @plan_id_key)
    |> maybe_add_plan_match_error(marker, plan, @tracker_kind_key, @tracker_kind_key)
    |> maybe_add_plan_match_error(marker, plan, @plan_revision_key, @revision_key)
  end

  defp maybe_add_plan_match_error(errors, marker, plan, marker_key, plan_key) do
    if Map.has_key?(marker, marker_key) and Map.has_key?(plan, plan_key) and Map.get(marker, marker_key) != Map.get(plan, plan_key) do
      errors ++
        [
          %{
            code: ErrorCodes.render_marker_mismatch(),
            path: [marker_key],
            message: "Render marker does not match the structured execution plan."
          }
        ]
    else
      errors
    end
  end

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""
  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp non_negative_integer?(value), do: is_integer(value) and value >= 0
  defp namespaced_key?(value) when is_binary(value), do: String.contains?(value, ".")
  defp namespaced_key?(_value), do: false
end
