defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.TargetRegistration do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Events

  @spec register(map(), map(), String.t(), term(), keyword()) :: :ok
  def register(attrs, tracker, tool, arguments, opts) when is_map(attrs) and is_map(tracker) and is_binary(tool) do
    opts
    |> Keyword.get(:register_known_target_fn, &Reconciliation.register_known_target/2)
    |> then(& &1.(attrs, opts))
    |> case do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        Events.ignored(
          tracker,
          tool,
          arguments,
          :known_target_registration_failed,
          %{error: Diagnostics.error_string(reason)},
          opts
        )

      _other ->
        :ok
    end
  end
end
