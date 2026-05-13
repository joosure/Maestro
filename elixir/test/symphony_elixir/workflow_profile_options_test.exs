defmodule SymphonyElixir.WorkflowProfileOptionsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Profile.Options

  @kind "test_profile"
  @defaults %{
    "enabled" => true,
    "mode" => "strict",
    "names" => [],
    "handler" => "land"
  }

  test "rejects unknown option keys" do
    assert :ok == Options.reject_unknown(@kind, %{"enabled" => false}, Map.keys(@defaults))

    assert {:error, {:unknown_profile_option, @kind, "unknown"}} =
             Options.reject_unknown(@kind, %{"unknown" => true}, Map.keys(@defaults))
  end

  test "validates boolean options against defaults" do
    assert :ok == Options.validate_boolean(@kind, %{}, @defaults, "enabled")
    assert :ok == Options.validate_boolean(@kind, %{"enabled" => false}, @defaults, "enabled")

    assert {:error, {:invalid_profile_option, @kind, "enabled", "false"}} =
             Options.validate_boolean(@kind, %{"enabled" => "false"}, @defaults, "enabled")
  end

  test "validates enum options against defaults" do
    assert :ok == Options.validate_enum(@kind, %{}, @defaults, "mode", ["strict", "loose"])
    assert :ok == Options.validate_enum(@kind, %{"mode" => "loose"}, @defaults, "mode", ["strict", "loose"])

    assert {:error, {:invalid_profile_option, @kind, "mode", "invalid"}} =
             Options.validate_enum(@kind, %{"mode" => "invalid"}, @defaults, "mode", ["strict", "loose"])
  end

  test "validates string-list options against defaults" do
    assert :ok == Options.validate_string_list(@kind, %{}, @defaults, "names")
    assert :ok == Options.validate_string_list(@kind, %{"names" => ["alpha"]}, @defaults, "names")

    assert {:error, {:invalid_profile_option, @kind, "names", [""]}} =
             Options.validate_string_list(@kind, %{"names" => [""]}, @defaults, "names")
  end

  test "validates normalized execution-profile style names" do
    assert :ok == Options.validate_name(@kind, %{}, @defaults, "handler")
    assert :ok == Options.validate_name(@kind, %{"handler" => "ship_1"}, @defaults, "handler")

    assert {:error, {:invalid_profile_option, @kind, "handler", "Ship"}} =
             Options.validate_name(@kind, %{"handler" => "Ship"}, @defaults, "handler")
  end
end
