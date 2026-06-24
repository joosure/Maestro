defmodule SymphonyElixir.Agent.DynamicTool.ResultRecorder do
  @moduledoc """
  Provider-neutral Dynamic Tool result-recorder dispatcher.

  Dynamic Tool sources publish tool execution results through this boundary so
  tracker, repo, and repo-provider sources do not depend on workflow or
  extension business modules. Application assembly decides which recorder
  modules receive the result.
  """

  @app :symphony_elixir
  @config_key :dynamic_tool_result_recorders
  @invalid_result_recorder "invalid_dynamic_tool_result_recorder"
  @result_type_success "success"
  @result_type_failure "failure"
  @result_type_error "error"

  @type source_kind :: String.t() | atom() | nil
  @type tool_result :: {:success, term()} | {:failure, term()} | {:error, term()} | term()

  @callback record_result(
              source_kind(),
              term(),
              String.t() | nil,
              term(),
              tool_result(),
              keyword()
            ) :: :ok | {:error, term()}

  @spec record_result(source_kind(), term(), String.t() | nil, term(), tool_result(), keyword()) ::
          :ok | {:error, map()}
  def record_result(source_kind, source_context, tool, arguments, result, opts \\ [])

  def record_result(source_kind, source_context, tool, arguments, result, opts) when is_list(opts) do
    opts
    |> recorder_modules()
    |> Enum.reduce_while(:ok, fn recorder, :ok ->
      case invoke_recorder(recorder, source_kind, source_context, tool, arguments, result, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, result_recorder_error(recorder, reason, source_kind, tool, result)}}
      end
    end)
  end

  def record_result(source_kind, _source_context, tool, _arguments, result, opts) do
    {:error, result_recorder_error(nil, {:invalid_options, diagnostic_type(opts)}, source_kind, tool, result)}
  end

  @spec result_type(tool_result()) :: String.t()
  def result_type({:success, _payload}), do: @result_type_success
  def result_type({:failure, _payload}), do: @result_type_failure
  def result_type({:error, _reason}), do: @result_type_error
  def result_type(result), do: diagnostic_type(result)

  defp recorder_modules(opts) do
    opts
    |> Keyword.get_lazy(:dynamic_tool_result_recorders, fn ->
      Application.get_env(@app, @config_key, [])
    end)
    |> List.wrap()
  end

  defp invoke_recorder(recorder, source_kind, source_context, tool, arguments, result, opts) do
    with :ok <- validate_recorder(recorder) do
      safe_record(recorder, source_kind, source_context, tool, arguments, result, opts)
    end
  end

  defp validate_recorder(recorder) when is_atom(recorder) and not is_nil(recorder) do
    cond do
      not Code.ensure_loaded?(recorder) ->
        {:error, :recorder_not_loaded}

      not function_exported?(recorder, :record_result, 6) ->
        {:error, :recorder_callback_missing}

      not implements_behaviour?(recorder, __MODULE__) ->
        {:error, :recorder_behaviour_missing}

      true ->
        :ok
    end
  end

  defp validate_recorder(_recorder), do: {:error, :invalid_recorder_module}

  defp safe_record(recorder, source_kind, source_context, tool, arguments, result, opts) do
    case recorder.record_result(source_kind, source_context, tool, arguments, result, opts) do
      :ok -> :ok
      {:error, reason} -> {:error, {:recorder_failed, result_diagnostic(reason)}}
      other -> {:error, {:invalid_recorder_result, diagnostic_type(other)}}
    end
  rescue
    error ->
      {:error, {:recorder_raised, Exception.message(error)}}
  catch
    kind, reason ->
      {:error, {:recorder_threw, kind, inspect(reason)}}
  end

  defp result_recorder_error(recorder, reason, source_kind, tool, result) do
    %{
      code: @invalid_result_recorder,
      message: "Dynamic Tool result recorder failed.",
      recorder_module: recorder_module(recorder),
      reason: result_diagnostic(reason),
      source_kind: source_kind_diagnostic(source_kind),
      tool: tool_diagnostic(tool),
      result_type: result_type(result)
    }
  end

  defp implements_behaviour?(module, behaviour) do
    attributes = module.module_info(:attributes)

    behaviours =
      Keyword.get_values(attributes, :behaviour) ++
        Keyword.get_values(attributes, :behavior)

    behaviour in List.flatten(behaviours)
  end

  defp result_diagnostic(reason) when is_atom(reason) and not is_nil(reason), do: reason
  defp result_diagnostic(reason) when is_binary(reason), do: String.slice(reason, 0, 256)

  defp result_diagnostic({reason, type}) when reason in [:invalid_options, :invalid_recorder_result] do
    %{reason: reason, value_type: type}
  end

  defp result_diagnostic({reason, nested}) when reason in [:recorder_failed, :recorder_raised] do
    %{reason: reason, details: result_diagnostic(nested)}
  end

  defp result_diagnostic({:recorder_threw, kind, details}) do
    %{reason: :recorder_threw, kind: kind, details: String.slice(to_string(details), 0, 256)}
  end

  defp result_diagnostic(reason), do: %{type: diagnostic_type(reason)}

  defp recorder_module(recorder) when is_atom(recorder) and not is_nil(recorder), do: inspect(recorder)
  defp recorder_module(_recorder), do: nil

  defp source_kind_diagnostic(source_kind) when is_atom(source_kind) and not is_nil(source_kind), do: Atom.to_string(source_kind)
  defp source_kind_diagnostic(source_kind) when is_binary(source_kind), do: String.slice(source_kind, 0, 128)
  defp source_kind_diagnostic(_source_kind), do: nil

  defp tool_diagnostic(tool) when is_binary(tool), do: String.slice(tool, 0, 128)
  defp tool_diagnostic(_tool), do: nil

  defp diagnostic_type(value) when is_atom(value) and not is_nil(value), do: "atom"
  defp diagnostic_type(value) when is_binary(value), do: "string"
  defp diagnostic_type(value) when is_boolean(value), do: "boolean"
  defp diagnostic_type(value) when is_integer(value), do: "integer"
  defp diagnostic_type(value) when is_float(value), do: "float"
  defp diagnostic_type(value) when is_list(value), do: "list"
  defp diagnostic_type(value) when is_map(value), do: "map"
  defp diagnostic_type(nil), do: "nil"
  defp diagnostic_type(_value), do: "term"
end
