defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.EventsEmitterTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.Emitter

  test "rejects non-keyword options without falling back to the host backend" do
    assert {:error,
            %{
              code: :invalid_reconciliation_event_emitter_options,
              value_type: "list"
            }} = Emitter.emit(:info, :change_proposal_reconciliation_started, %{}, [:not_keyword])
  end

  test "rejects invalid backend modules without raising" do
    assert {:error,
            %{
              code: :invalid_reconciliation_event_emitter_backend,
              value_type: "atom"
            }} = Emitter.emit(:info, :change_proposal_reconciliation_started, %{}, backend: __MODULE__.MissingBackend)
  end
end
