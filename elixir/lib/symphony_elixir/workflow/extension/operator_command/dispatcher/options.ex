defmodule SymphonyElixir.Workflow.Extension.OperatorCommand.Dispatcher.Options do
  @moduledoc """
  Option-boundary validation for workflow extension operator-command dispatch.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.ErrorCodes

  @spec normalize(term()) :: {:ok, %{registry_opts: keyword(), command_opts: keyword()}} | {:error, map()}
  def normalize(opts) when is_list(opts) do
    with :ok <- keyword_opts(opts, :dispatcher_opts_not_keyword, opts),
         {:ok, registry_opts} <- keyword_option(opts, :registry_opts),
         {:ok, command_opts} <- keyword_option(opts, :command_opts) do
      {:ok, %{registry_opts: registry_opts, command_opts: command_opts}}
    end
  end

  def normalize(opts), do: {:error, error(:dispatcher_opts_not_keyword, opts)}

  defp keyword_option(opts, key) do
    value = Keyword.get(opts, key, [])

    with :ok <- keyword_opts(value, {:dispatcher_option_not_keyword, key}, value) do
      {:ok, value}
    end
  end

  defp keyword_opts(opts, reason, _value) when is_list(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, error(reason, opts)}
  end

  defp keyword_opts(_opts, reason, value), do: {:error, error(reason, value)}

  defp error(reason, value) do
    %{
      code: ErrorCodes.invalid_operator_command(),
      message: "Workflow extension operator command dispatch options are invalid.",
      reason: reason,
      value_type: Diagnostics.type_name(value)
    }
  end
end
