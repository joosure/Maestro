defmodule SymphonyElixir.Platform.EnvTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Platform.Env

  test "nested preserves explicit false values" do
    settings = %{
      agent: %{
        credentials: %{
          enabled: false
        }
      }
    }

    assert Env.nested(settings, [:agent, :credentials, :enabled]) == false
  end

  test "nested falls back to string keys when atom keys are absent" do
    settings = %{
      "agent" => %{
        "credentials" => %{
          "enabled" => true
        }
      }
    }

    assert Env.nested(settings, [:agent, :credentials, :enabled])
  end
end
