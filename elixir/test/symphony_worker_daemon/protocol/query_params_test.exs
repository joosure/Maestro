defmodule SymphonyWorkerDaemon.Protocol.QueryParamsTest do
  use ExUnit.Case, async: true

  alias SymphonyWorkerDaemon.Protocol.QueryParams

  test "session query params keep supported filters and normalize values" do
    query =
      QueryParams.session(%{
        "owner" => "owner-a",
        "tenant_id" => " ",
        "run_id" => 123,
        "status" => :running,
        "ignored" => "value"
      })

    assert URI.decode_query(query) == %{
             "owner" => "owner-a",
             "run_id" => "123",
             "status" => "running"
           }
  end

  test "event query params keep event filters and normalize keyword values" do
    query = QueryParams.events(after_event_id: 10, limit: " 25 ", ignored: "value")

    assert URI.decode_query(query) == %{
             "after_event_id" => "10",
             "limit" => "25"
           }
  end

  test "empty query params encode as an empty string" do
    assert QueryParams.session(%{"unknown" => "value"}) == ""
    assert QueryParams.events(ignored: "value") == ""
  end
end
