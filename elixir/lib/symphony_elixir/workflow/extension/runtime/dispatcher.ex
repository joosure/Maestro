defmodule SymphonyElixir.Workflow.Extension.Runtime.Dispatcher do
  @moduledoc """
  Sequential dispatcher for registered workflow runtime extensions.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.Registry
  alias SymphonyElixir.Workflow.Extension.Runtime.Context, as: RuntimeContext
  alias SymphonyElixir.Workflow.Extension.Runtime.Error
  alias SymphonyElixir.Workflow.Extension.Runtime.Options
  alias SymphonyElixir.Workflow.Extension.Runtime.Result, as: RuntimeResult
  alias SymphonyElixir.Workflow.Extension.Runtime.ResultApplier

  @type runtime_state :: map()

  @spec run_poll_cycle(RuntimeContext.t(), runtime_state(), keyword()) ::
          {:ok, runtime_state()} | {:error, map()}
  def run_poll_cycle(%RuntimeContext{} = context, runtime_state, opts)
      when is_map(runtime_state) and is_list(opts) do
    with {:ok, entries} <- Registry.entries(Options.registry_opts(opts)),
         {:ok, extension_opts_by_id} <- Options.by_extension(entries, opts) do
      entries
      |> Enum.reduce_while({:ok, runtime_state}, fn entry, {:ok, current_state} ->
        context = RuntimeContext.refresh_runtime(context, current_state)

        case invoke_extension(entry, context, Map.fetch!(extension_opts_by_id, entry.id)) do
          {:ok, {:ok, %RuntimeResult{} = result}} ->
            case ResultApplier.apply(current_state, entry.id, result, opts) do
              {:ok, updated_state} -> {:cont, {:ok, updated_state}}
              {:error, reason} -> {:halt, {:error, Error.extension(entry, reason)}}
            end

          {:ok, {:ok, invalid_result}} ->
            {:halt, {:error, Error.extension(entry, {:invalid_result, invalid_result})}}

          {:ok, {:error, reason}} ->
            {:halt, {:error, Error.extension(entry, reason)}}

          {:error, reason} ->
            {:halt, {:error, Error.extension(entry, reason)}}

          {:ok, other} ->
            {:halt, {:error, Error.extension(entry, {:invalid_result, other})}}
        end
      end)
    end
  end

  defp invoke_extension(entry, context, opts) do
    {:ok, entry.module.run_poll_cycle(context, opts)}
  rescue
    error ->
      {:error, Diagnostics.exception(error)}
  catch
    kind, reason ->
      {:error, Diagnostics.caught(kind, reason)}
  end
end
