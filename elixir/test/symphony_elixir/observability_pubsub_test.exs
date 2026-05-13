defmodule SymphonyElixir.ObservabilityPubSubTest do
  use SymphonyElixir.TestSupport
  import ExUnit.CaptureLog

  alias SymphonyElixirWeb.ObservabilityPubSub

  test "subscribe and broadcast_update deliver dashboard updates" do
    log =
      capture_log(fn ->
        assert :ok = ObservabilityPubSub.subscribe()
        assert :ok = ObservabilityPubSub.broadcast_update()
        assert_receive :observability_updated
      end)

    assert log =~ "dashboard_pubsub_subscribed topic=observability:dashboard"
  end

  test "broadcast_update is a no-op when pubsub is unavailable" do
    pubsub_child_id = Phoenix.PubSub.Supervisor

    on_exit(fn ->
      if Process.whereis(SymphonyElixir.PubSub) == nil do
        assert :ok = restart_pubsub_child(pubsub_child_id)
      end
    end)

    assert is_pid(Process.whereis(SymphonyElixir.PubSub))
    assert :ok = terminate_supervised_child(pubsub_child_id)
    refute Process.whereis(SymphonyElixir.PubSub)

    log =
      capture_log(fn ->
        assert {:error, :unavailable} = ObservabilityPubSub.subscribe()
        assert :ok = ObservabilityPubSub.broadcast_update()
      end)

    assert log =~ "dashboard_pubsub_subscribe_failed topic=observability:dashboard error=pubsub_unavailable"
    assert log =~ "dashboard_pubsub_broadcast_skipped topic=observability:dashboard reason=pubsub_unavailable"
  end

  defp restart_pubsub_child(pubsub_child_id) do
    case restart_supervised_child(pubsub_child_id) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      other -> flunk("Expected pubsub child restart to succeed, got: #{inspect(other)}")
    end
  end
end
