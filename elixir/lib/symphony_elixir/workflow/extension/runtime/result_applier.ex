defmodule SymphonyElixir.Workflow.Extension.Runtime.ResultApplier do
  @moduledoc """
  Applies runtime extension results back into the platform runtime envelope.
  """

  alias SymphonyElixir.Workflow.Extension.Runtime.CommandExecutor
  alias SymphonyElixir.Workflow.Extension.Runtime.Result, as: RuntimeResult

  @spec apply(map(), String.t(), RuntimeResult.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def apply(runtime_state, extension_id, %RuntimeResult{} = result, opts)
      when is_map(runtime_state) and is_binary(extension_id) and is_list(opts) do
    with :ok <- CommandExecutor.execute(result.commands, opts) do
      {:ok, put_extension_state(runtime_state, extension_id, result.extension_state)}
    end
  end

  defp put_extension_state(runtime_state, extension_id, extension_state) when is_map(extension_state) do
    workflow_extensions =
      runtime_state
      |> Map.get(:workflow_extensions, %{})
      |> case do
        states when is_map(states) -> states
        _states -> %{}
      end

    Map.put(runtime_state, :workflow_extensions, Map.put(workflow_extensions, extension_id, extension_state))
  end
end
