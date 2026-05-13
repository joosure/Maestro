defmodule SymphonyWorkerDaemon.Protocol.Validation.FieldsTest do
  use ExUnit.Case, async: true

  alias SymphonyWorkerDaemon.Protocol.Validation.Fields

  test "allowed_keys rejects unknown fields with sorted names" do
    assert Fields.allowed_keys(%{"known" => 1, other: 2, another: 3}, "request", ["known"]) ==
             {:error, {:payload_unknown_fields, "request", ["another", "other"]}}
  end

  test "allowed_nested_keys validates optional nested maps" do
    assert Fields.allowed_nested_keys(%{}, "caller", ["owner"]) == :ok
    assert Fields.allowed_nested_keys(%{"caller" => %{"owner" => "owner-a"}}, "caller", ["owner"]) == :ok
    assert Fields.allowed_nested_keys(%{"caller" => "owner-a"}, "caller", ["owner"]) == {:error, {:payload_invalid, "caller"}}
  end

  test "optional map and string validators accept absent values only with correct shape" do
    assert Fields.optional_map(%{}, "env") == :ok
    assert Fields.optional_map(%{"env" => %{"A" => "B"}}, "env") == :ok
    assert Fields.optional_map(%{"env" => []}, "env") == {:error, {:payload_invalid, "env"}}

    assert Fields.optional_string(%{}, "reason") == :ok
    assert Fields.optional_string(%{"reason" => "operator_stop"}, "reason") == :ok
    assert Fields.optional_string(%{"reason" => :operator_stop}, "reason") == {:error, {:payload_invalid, "reason"}}
  end
end
