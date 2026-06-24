defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.WorkflowRef do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics

  @spec resolve(keyword(), map()) :: {:ok, Path.t(), String.t()} | {:error, map()}
  def resolve(opts, deps) when is_list(opts) and is_map(deps) do
    template = opts |> Keyword.get(:template) |> normalize_optional_string()
    workflow_path = opts |> Keyword.get(:workflow_path) |> normalize_optional_string()

    cond do
      is_binary(template) ->
        resolve_template(template, deps)

      is_binary(workflow_path) ->
        resolve_explicit_workflow_path(workflow_path, deps)

      true ->
        resolve_default_workflow_path(deps)
    end
  end

  defp resolve_template(template, deps) do
    case deps.resolve_template.(template) do
      {:ok, path} ->
        {:ok, path, "template:#{template}"}

      {:error, reason} ->
        {:error,
         %{
           code: :workflow_template_resolution_failed,
           source: :template,
           reason_type: Diagnostics.type_name(reason)
         }}
    end
  end

  defp resolve_explicit_workflow_path(workflow_path, deps) do
    expanded = Path.expand(workflow_path)

    if deps.file_regular?.(expanded) do
      {:ok, expanded, expanded}
    else
      {:error, %{code: :workflow_file_not_found, source: :explicit_workflow_path}}
    end
  end

  defp resolve_default_workflow_path(deps) do
    path = deps.workflow_file_path.()

    if deps.file_regular?.(path) do
      {:ok, path, path}
    else
      {:error, %{code: :workflow_file_not_found, source: :default_workflow_path}}
    end
  end

  defp normalize_optional_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  defp normalize_optional_string(value) when is_integer(value), do: value |> Integer.to_string() |> normalize_optional_string()
  defp normalize_optional_string(_value), do: nil
end
