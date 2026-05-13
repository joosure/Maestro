defmodule SymphonyWorkerDaemon.Protocol.ValidationTest do
  use ExUnit.Case, async: true

  alias SymphonyWorkerDaemon.Protocol
  alias SymphonyWorkerDaemon.Protocol.Validation

  test "accepts valid create requests with bridge and policy fields" do
    request =
      create_request(%{
        "required_features" => ["session_create", "session_status"],
        "dynamic_tool_bridge" => %{
          "transport" => "worker_daemon_http",
          "symphony_base_url" => "https://tools.example.com/api/v1/agent-tools/dynamic",
          "token" => "tool-token",
          "provider_env" => %{"TOOL_ENV" => "enabled"}
        },
        "timeout_policy" => %{
          "startup_timeout_ms" => "100",
          "idle_timeout_ms" => 200,
          "session_timeout_ms" => 1_000
        },
        "resource_budget" => %{
          "output_buffer_bytes" => "4096",
          "max_output_bytes" => 8192
        }
      })

    assert :ok = validate_create(request)
  end

  test "rejects unsupported required create features" do
    request = create_request(%{"required_features" => ["session_create", "unknown_feature"]})

    assert validate_create(request) ==
             {:error, {:unsupported_required_features, ["unknown_feature"]}}
  end

  test "rejects unknown dynamic tool bridge fields" do
    request =
      create_request(%{
        "dynamic_tool_bridge" => %{
          "transport" => "worker_daemon_http",
          "symphony_base_url" => "https://tools.example.com/api/v1/agent-tools/dynamic",
          "token" => "tool-token",
          "redirect_url" => "https://other.example.com"
        }
      })

    assert validate_create(request) ==
             {:error, {:payload_unknown_fields, "dynamic_tool_bridge", ["redirect_url"]}}
  end

  test "rejects invalid timeout and resource budget fields" do
    timeout_request =
      create_request(%{
        "timeout_policy" => %{"idle_timeout_ms" => "not-an-integer"}
      })

    resource_request =
      create_request(%{
        "resource_budget" => %{"cpu_ms" => 100}
      })

    assert validate_create(timeout_request) ==
             {:error, {:payload_invalid, "timeout_policy.idle_timeout_ms"}}

    assert validate_create(resource_request) ==
             {:error, {:payload_unknown_fields, "resource_budget", ["cpu_ms"]}}
  end

  test "enforces create request dynamic tool bridge byte limit" do
    request =
      create_request(%{
        "dynamic_tool_bridge" => %{
          "transport" => "worker_daemon_http",
          "symphony_base_url" => "https://tools.example.com/api/v1/agent-tools/dynamic",
          "token" => "tool-token"
        }
      })

    assert {:error, {:payload_too_large, "dynamic_tool_bridge", actual_bytes, 8}} =
             validate_create(request, max_protocol_dynamic_tool_bridge_bytes: 8)

    assert actual_bytes > 8
  end

  defp validate_create(request, opts \\ []) do
    Validation.validate_create_request(
      request,
      Protocol.supported_features(),
      Keyword.put(opts, :protocol_version, Protocol.protocol_version())
    )
  end

  defp create_request(attrs) when is_map(attrs) do
    Map.merge(
      %{
        "protocol_version" => Protocol.protocol_version(),
        "request_id" => "request-validation",
        "session_id" => "session-validation",
        "run_id" => "run-validation",
        "caller" => %{
          "provider_kind" => "fake",
          "worker_pool" => "coding-linux",
          "owner" => "symphony"
        },
        "command" => %{"mode" => "argv", "argv" => ["fake-provider"]},
        "workspace" => %{"cwd" => "/workspace"},
        "env" => %{}
      },
      attrs
    )
  end
end
