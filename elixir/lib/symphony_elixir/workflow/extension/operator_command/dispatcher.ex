defmodule SymphonyElixir.Workflow.Extension.OperatorCommand.Dispatcher do
  @moduledoc """
  Dispatcher for workflow extension operator commands.

  Platform operator entrypoints dispatch by command id through this module
  instead of depending on concrete workflow extension business modules. Concrete
  command parsing and execution stay inside the owning extension command module.
  """

  alias SymphonyElixir.Workflow.Extension.{Diagnostics, ErrorCodes}
  alias SymphonyElixir.Workflow.Extension.OperatorCommand.Dispatcher.Options
  alias SymphonyElixir.Workflow.Extension.OperatorCommand.Registry

  @type result :: {String.t(), String.t(), non_neg_integer()}

  @spec evaluate(String.t(), [String.t()], keyword()) :: result()
  def evaluate(command_id, argv, opts \\ [])

  def evaluate(command_id, argv, opts) when is_binary(command_id) and is_list(argv) do
    with {:ok, %{registry_opts: registry_opts, command_opts: command_opts}} <- Options.normalize(opts),
         {:ok, entry} <- Registry.fetch(command_id, registry_opts) do
      invoke(entry, argv, command_opts)
    else
      {:error, reason} -> {"", format_error(reason), 69}
    end
  end

  def evaluate(_command_id, _argv, opts) do
    case Options.normalize(opts) do
      {:ok, _opts} -> {"", "Workflow extension operator command arguments are invalid.", 69}
      {:error, reason} -> {"", format_error(reason), 69}
    end
  end

  defp invoke(entry, argv, opts) do
    case safe_evaluate(entry.module, argv, opts) do
      {:ok, {stdout, stderr, exit_code}} when is_binary(stdout) and is_binary(stderr) and is_integer(exit_code) and exit_code >= 0 ->
        {stdout, stderr, exit_code}

      {:ok, invalid_result} ->
        {"", "Workflow extension operator command returned an invalid result type: #{Diagnostics.type_name(invalid_result)}", 70}

      {:error, reason} ->
        {"", "Workflow extension operator command failed: #{format_failure(reason)}", 70}
    end
  end

  defp safe_evaluate(module, argv, opts) do
    {:ok, module.evaluate(argv, opts)}
  rescue
    error ->
      {:error, Diagnostics.exception(error)}
  catch
    kind, reason ->
      {:error, Diagnostics.caught(kind, reason)}
  end

  defp format_failure(%{kind: :error, exception: exception}) when is_binary(exception), do: "exception=#{exception}"
  defp format_failure(%{kind: kind, reason_type: reason_type}) when is_binary(reason_type), do: "kind=#{kind} reason_type=#{reason_type}"
  defp format_failure(reason), do: "reason_type=#{Diagnostics.type_name(reason)}"

  defp format_error(%{code: code, reason: reason} = error) do
    if code == ErrorCodes.invalid_operator_command() do
      case reason do
        :operator_command_not_found ->
          "Workflow extension operator command not found: #{Map.get(error, :command_id)}"

        _reason ->
          "Workflow extension operator command registration is invalid: reason=#{format_reason(reason)}"
      end
    else
      "Workflow extension operator command failed: code=#{code} reason=#{format_reason(reason)}"
    end
  end

  defp format_error(reason), do: "Workflow extension operator command failed: reason_type=#{Diagnostics.type_name(reason)}"

  defp format_reason(reason) when is_atom(reason) and not is_nil(reason), do: Atom.to_string(reason)

  defp format_reason({reason, key}) when is_atom(reason) and is_atom(key) do
    "#{reason}:#{key}"
  end

  defp format_reason(reason), do: "type=#{Diagnostics.type_name(reason)}"
end
