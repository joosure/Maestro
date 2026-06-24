defmodule SymphonyElixir.Workflow.Extension.ToolResultRecorder.Dispatcher do
  @moduledoc """
  Dispatcher for workflow extension Dynamic Tool result recorders.

  Platform assembly calls this module with provider-neutral Dynamic Tool
  execution results. Concrete extensions decide whether and how to interpret
  the result.
  """

  alias SymphonyElixir.Agent.DynamicTool.ResultRecorder
  alias SymphonyElixir.Workflow.Extension.{Diagnostics, ErrorCodes}
  alias SymphonyElixir.Workflow.Extension.ToolResultRecorder.Registry

  @spec record_tool_result(String.t() | atom() | nil, term(), String.t() | nil, term(), term(), keyword()) ::
          :ok | {:error, map()}
  def record_tool_result(source_kind, source_context, tool, arguments, result, opts \\ []) do
    with {:ok, opts} <- normalize_opts(opts),
         {:ok, registry_opts} <- keyword_option(opts, :tool_result_recorder_registry_opts, []),
         {:ok, recorder_opts} <- keyword_option(opts, :tool_result_recorder_opts, []) do
      dispatch(entries_opts: registry_opts, recorder_opts: recorder_opts, source_kind: source_kind, source_context: source_context, tool: tool, arguments: arguments, result: result)
    end
  end

  defp dispatch(entries_opts: registry_opts, recorder_opts: recorder_opts, source_kind: source_kind, source_context: source_context, tool: tool, arguments: arguments, result: result) do
    with {:ok, entries} <- Registry.entries(registry_opts) do
      Enum.reduce_while(entries, :ok, fn entry, :ok ->
        case invoke(entry, source_kind, source_context, tool, arguments, result, recorder_opts) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, recorder_error(entry, reason, source_kind, tool, result)}}
        end
      end)
    end
  end

  defp normalize_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, opts}
    else
      {:error, dispatch_error(:dispatcher_opts_not_keyword, opts)}
    end
  end

  defp normalize_opts(opts), do: {:error, dispatch_error(:dispatcher_opts_not_keyword, opts)}

  defp keyword_option(opts, key, default) do
    value = Keyword.get(opts, key, default)

    cond do
      is_list(value) and Keyword.keyword?(value) ->
        {:ok, value}

      is_list(value) ->
        {:error, dispatch_error({:dispatcher_option_not_keyword, key}, value)}

      true ->
        {:error, dispatch_error({:dispatcher_option_not_keyword, key}, value)}
    end
  end

  defp invoke(entry, source_kind, source_context, tool, arguments, result, opts) do
    case safe_record(entry.module, source_kind, source_context, tool, arguments, result, opts) do
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> {:error, {:recorder_failed, Diagnostics.type_name(reason)}}
      {:ok, other} -> {:error, {:invalid_recorder_result, Diagnostics.type_name(other)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_record(module, source_kind, source_context, tool, arguments, result, opts) do
    {:ok, module.record_tool_result(source_kind, source_context, tool, arguments, result, opts)}
  rescue
    error ->
      {:error, %{kind: :error, exception: inspect(error.__struct__)}}
  catch
    kind, reason ->
      {:error, %{kind: kind, reason_type: Diagnostics.type_name(reason)}}
  end

  defp recorder_error(entry, reason, source_kind, tool, result) do
    %{
      code: ErrorCodes.tool_result_recorder_error(),
      message: "Workflow extension tool-result recorder failed.",
      recorder_id: entry.id,
      recorder_module: inspect(entry.module),
      reason: bounded_reason(reason),
      source_kind: source_kind_diagnostic(source_kind),
      tool: tool_diagnostic(tool),
      result_type: ResultRecorder.result_type(result)
    }
  end

  defp bounded_reason({reason, type}) when reason in [:invalid_recorder_result, :recorder_failed] do
    %{reason: reason, value_type: type}
  end

  defp bounded_reason(%{kind: kind, exception: exception}) when is_binary(exception) do
    %{kind: kind, exception: exception}
  end

  defp bounded_reason(%{kind: kind, reason_type: reason_type}) when is_binary(reason_type) do
    %{kind: kind, reason_type: reason_type}
  end

  defp bounded_reason(reason), do: %{type: Diagnostics.type_name(reason)}

  defp source_kind_diagnostic(source_kind) when is_atom(source_kind) and not is_nil(source_kind), do: Atom.to_string(source_kind)
  defp source_kind_diagnostic(source_kind) when is_binary(source_kind), do: String.slice(source_kind, 0, 128)
  defp source_kind_diagnostic(_source_kind), do: nil

  defp tool_diagnostic(tool) when is_binary(tool), do: String.slice(tool, 0, 128)
  defp tool_diagnostic(_tool), do: nil

  defp dispatch_error(reason, value) do
    %{
      code: ErrorCodes.invalid_tool_result_recorder(),
      message: "Workflow extension tool-result recorder dispatch options are invalid.",
      reason: reason,
      value_type: Diagnostics.type_name(value)
    }
  end
end
