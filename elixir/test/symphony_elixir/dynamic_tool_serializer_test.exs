defmodule SymphonyElixir.Agent.DynamicTool.SerializerTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.DynamicTool.Bridge.Result
  alias SymphonyElixir.Agent.DynamicTool.{ErrorProjector, Serializer}
  alias SymphonyElixir.Tracker.Error, as: TrackerError

  defmodule UnknownError do
    defstruct [:code, :message, :details]
  end

  test "public error details only exposes canonical allowlisted string keys" do
    details = %{
      "field" => "sideEffect",
      "body" => "secret",
      "source_reason" => {:internal, :reason},
      "unknown" => "ignored",
      option: :legacy_atom_key
    }

    assert Serializer.public_error_details(details) == %{"field" => "sideEffect"}
  end

  test "json_safe_value remains a last-resort provider-boundary sanitizer" do
    payload = %{
      :ok => :yes,
      1 => {:bad, :key},
      "safe" => [%{nested: :atom}]
    }

    assert Serializer.json_safe_value(payload) == %{
             "ok" => "yes",
             "1" => "{:bad, :key}",
             "safe" => [%{"nested" => "atom"}]
           }
  end

  test "error projector explicitly projects known tracker errors" do
    error =
      TrackerError.new(%{
        provider: "tapd",
        operation: :fetch_issue,
        code: :not_found,
        message: "Tracker issue was not found.",
        retryable?: true,
        details: %{
          option: :issue_id,
          status: 404,
          body: "secret response body",
          source_reason: {:provider_error, :secret}
        }
      })

    {:ok, payload} = ErrorProjector.project(error)

    assert payload["code"] == "not_found"
    assert payload["message"] == "Tracker issue was not found."
    assert payload["provider"] == "tapd"
    assert payload["operation"] == "fetch_issue"
    assert payload["retryable"] == true
    assert payload["details"] == %{"option" => "issue_id", "status" => 404}
  end

  test "error projector refuses unknown structs" do
    assert ErrorProjector.project(%UnknownError{code: :bad, message: "bad", details: %{field: :capability}}) == :error
  end

  test "bridge result does not duck type unknown error structs" do
    result = Result.normalize({:error, %UnknownError{code: :bad, message: "bad", details: %{"field" => "capability"}}})
    error = get_in(result, ["payload", "error"])

    assert error["message"] == "Dynamic tool execution failed."
    assert error["reason"] =~ "UnknownError"
    refute Map.has_key?(error, "code")
    refute Map.has_key?(error, "details")
  end
end
