defmodule SymphonyElixir.Observability.LoggerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  require Logger

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger

  test "emit inherits request_id from logger metadata and derives correlation_id" do
    Logger.metadata(request_id: "req-123")

    capture_log(fn ->
      send(
        self(),
        {:payload,
         ObservabilityLogger.emit(:info, :observability_test_event, %{
           component: "observability.logger_test"
         })}
      )
    end)

    assert_receive {:payload, payload}
    assert payload["request_id"] == "req-123"
    assert payload["correlation_id"] == "req-123"
  end

  test "emit derives correlation_id from run_id when request_id is absent" do
    capture_log(fn ->
      send(
        self(),
        {:payload,
         ObservabilityLogger.emit(:info, :observability_test_event, %{
           component: "observability.logger_test",
           run_id: "run-123"
         })}
      )
    end)

    assert_receive {:payload, payload}
    assert payload["run_id"] == "run-123"
    assert payload["correlation_id"] == "run-123"
  end
end
