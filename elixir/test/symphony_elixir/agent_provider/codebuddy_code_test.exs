defmodule SymphonyElixir.AgentProvider.CodeBuddyCodeTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.Credential.Store
  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.AgentProvider.CodeBuddyCode
  alias SymphonyElixir.AgentProvider.CodeBuddyCode.{AuxiliaryHttp, CommandRenderer, CredentialEnv, Settings, Tooling}
  alias SymphonyElixir.AgentProvider.Config, as: ProviderConfig
  alias SymphonyElixir.AgentProvider.{Error, TurnResult}
  alias SymphonyElixir.Platform.Process, as: PlatformProcess

  @provider_kind "codebuddy_code"
  @acp_stdio_read_timeout_ms 5_000
  @acp_http_read_timeout_ms 3_000
  @acp_http_auto_port_startup_timeout_ms 10_000

  defmodule CodeBuddyHttpTestPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      {:ok, body, conn} = read_body(conn)
      record_request(opts, request_snapshot(conn, body))

      case {conn.method, conn.request_path, decode_json(body)} do
        {"GET", "/api/v1/auth/status", _body} ->
          json(conn, 200, %{"authEnabled" => Keyword.get(opts, :gateway_phrase) != nil, "authenticated" => false})

        {"GET", path, _body} when path in ["/api/v1/health", "/api/v1/info", "/api/v1/metrics", "/api/v1/stats/session", "/api/v1/plugins"] ->
          if gateway_authorized?(conn, opts) do
            auxiliary_response(conn, path, opts)
          else
            json(conn, 401, %{"error" => %{"code" => "AUTH_REQUIRED", "message" => "auth required"}})
          end

        {"POST", "/api/v1/acp/connect", _body} ->
          json(conn, 200, %{"connectionId" => "test-connection-id", "sessionToken" => "test-session-token"})

        {"POST", "/api/v1/acp", %{"method" => "initialize", "id" => id}} ->
          sse(conn, [
            %{
              "jsonrpc" => "2.0",
              "id" => id,
              "result" => %{
                "protocolVersion" => 1,
                "agentCapabilities" => %{"promptCapabilities" => %{}, "mcpCapabilities" => %{}, "loadSession" => true},
                "authMethods" => []
              }
            }
          ])

        {"POST", "/api/v1/acp", %{"method" => "session/new", "id" => id}} ->
          sse(conn, [
            %{
              "jsonrpc" => "2.0",
              "method" => "session/update",
              "params" => %{
                "sessionId" => "codebuddy-http-session-1",
                "update" => %{"sessionUpdate" => "available_commands_update", "availableCommands" => []}
              }
            },
            %{
              "jsonrpc" => "2.0",
              "id" => id,
              "result" => %{
                "sessionId" => "codebuddy-http-session-1",
                "models" => %{"availableModels" => [], "currentModelId" => "glm-5.1"},
                "modes" => %{"availableModes" => [%{"id" => "plan"}], "currentModeId" => "plan"},
                "configOptions" => []
              }
            }
          ])

        {"POST", "/api/v1/acp", %{"method" => "session/prompt", "id" => id}} ->
          Process.sleep(Keyword.get(opts, :prompt_delay_ms, 0))

          sse(conn, [
            %{
              "jsonrpc" => "2.0",
              "method" => "session/update",
              "params" => %{
                "sessionId" => "codebuddy-http-session-1",
                "update" => %{
                  "sessionUpdate" => "agent_message_chunk",
                  "content" => %{"type" => "text", "text" => "pong over http"},
                  "messageId" => "assistant-message-http-1"
                }
              }
            },
            %{
              "jsonrpc" => "2.0",
              "id" => id,
              "result" => %{
                "stopReason" => "end_turn",
                "userMessageId" => "codebuddy-http-user-message-1",
                "_meta" => %{"codebuddy.ai/finishReason" => "stop", "codebuddy.ai/requestId" => "secret-http-request-id"}
              }
            }
          ])

        {"POST", "/api/v1/acp", %{"method" => "session/cancel"}} ->
          send_resp(conn, 202, "")

        {"DELETE", "/api/v1/acp", _body} ->
          send_resp(conn, 200, "")

        _other ->
          json(conn, 404, %{"error" => "not found"})
      end
    end

    defp record_request(opts, snapshot) do
      if request_log = opts[:request_log] do
        Agent.update(request_log, &(&1 ++ [snapshot]))
      else
        send(opts[:owner], {:codebuddy_http_request, snapshot})
      end
    end

    defp request_snapshot(conn, body) do
      %{
        method: conn.method,
        path: conn.request_path,
        query_string: conn.query_string,
        accept: get_req_header(conn, "accept"),
        authorization: get_req_header(conn, "authorization"),
        acp_connection_id: get_req_header(conn, "acp-connection-id"),
        codebuddy_request: get_req_header(conn, "x-codebuddy-request"),
        body: body
      }
    end

    defp gateway_authorized?(conn, opts) do
      case Keyword.get(opts, :gateway_phrase) do
        nil -> true
        password -> get_req_header(conn, "authorization") == ["Bearer " <> password]
      end
    end

    defp auxiliary_response(conn, "/api/v1/health", opts) do
      json(
        conn,
        Keyword.get(opts, :health_status, 200),
        Keyword.get(opts, :health_body, %{"data" => %{"status" => "ok", "uptime" => 12, "platforms" => ["darwin"]}})
      )
    end

    defp auxiliary_response(conn, "/api/v1/info", _opts) do
      json(conn, 200, %{
        "data" => %{
          "version" => "2.97.2",
          "nodeVersion" => "v22.17.0",
          "os" => "darwin",
          "arch" => "arm64",
          "gatewayMode" => "local",
          "uptime" => 13,
          "cwd" => "/private/workspace/redacted-path",
          "tunnelUrl" => "https://redacted-tunnel.example",
          "userName" => "alice"
        }
      })
    end

    defp auxiliary_response(conn, "/api/v1/metrics", _opts) do
      json(conn, 200, %{
        "data" => %{
          "cpuCount" => 8,
          "cpuUsedPct" => 12.5,
          "diskTotal" => 1_000,
          "diskUsed" => 250,
          "memTotalMib" => 16_384,
          "memUsedMib" => 4_096,
          "ts" => 1_763_000_000,
          "instances" => [
            %{"pid" => 123, "command" => "codebuddy --prompt redacted", "cwd" => "/private/workspace/redacted-path"}
          ]
        }
      })
    end

    defp auxiliary_response(conn, "/api/v1/stats/session", _opts) do
      json(conn, 200, %{
        "data" => %{
          "apiDuration" => 20,
          "fileChangeStats" => %{"created" => 1, "paths" => ["/private/workspace/redacted-path/file.ex"]},
          "runningTime" => 30,
          "startupTime" => 10,
          "tokenUsageByModel" => %{"glm-5.1" => %{"input_tokens" => 111, "output_tokens" => 222}},
          "prompt" => "redacted prompt text"
        }
      })
    end

    defp auxiliary_response(conn, "/api/v1/plugins", _opts) do
      json(conn, 200, %{
        "data" => [
          %{
            "id" => "safe-plugin",
            "name" => "Safe Plugin",
            "version" => "1.0.0",
            "enabled" => true,
            "sourceType" => "generated",
            "rootPath" => "/private/workspace/redacted-plugin",
            "hookBody" => "redacted hook"
          }
        ]
      })
    end

    defp decode_json(""), do: %{}

    defp decode_json(body) when is_binary(body) do
      case Jason.decode(body) do
        {:ok, decoded} -> decoded
        {:error, _reason} -> %{}
      end
    end

    defp json(conn, status, payload) do
      conn
      |> put_resp_header("content-type", "application/json")
      |> send_resp(status, Jason.encode!(payload))
    end

    defp sse(conn, events) do
      conn = put_resp_header(conn, "content-type", "text/event-stream")
      conn = send_chunked(conn, 200)
      {:ok, conn} = chunk(conn, ":ok\n\n" <> Enum.map_join(events, "", &sse_event/1))
      conn
    end

    defp sse_event(payload), do: "event: message\ndata: " <> Jason.encode!(payload) <> "\n\n"
  end

  test "kind aliases normalize and registry exposes the adapter" do
    assert SymphonyElixir.AgentProvider.Kinds.normalize("codebuddy") == @provider_kind
    assert SymphonyElixir.AgentProvider.Kinds.normalize("CodeBuddyCode") == @provider_kind
    assert AgentProvider.adapter_for(@provider_kind) == CodeBuddyCode.Adapter
  end

  test "settings validation rejects unknown and non-MVP options" do
    assert {:error, {:unsupported_agent_provider_options, @provider_kind, ["unknown"]}} =
             CodeBuddyCode.Adapter.validate_options(%{unknown: true})

    assert :ok =
             CodeBuddyCode.Adapter.validate_options(%{
               credential_ref: "credential://codebuddy_code/default"
             })

    assert :ok =
             CodeBuddyCode.Adapter.validate_options(%{
               transport: "acp_http",
               http: %{enabled: true, allowlist: ["health", "version", "metrics_summary", "session_stats", "plugin_inventory"]}
             })

    for options <- [
          %{command: "codebuddy", command_argv: ["codebuddy"]},
          %{mcp: %{unknown: true}},
          %{plugin: %{enabled: true}},
          %{telemetry: %{enabled: true}},
          %{credential_ref: "credential://codebuddy_code/default", env: %{"CODEBUDDY_AUTH_TOKEN" => "unmanaged"}},
          %{quota_probe: %{enabled: true}},
          %{acp: %{client_file_proxy: true}},
          %{acp: %{client_terminal_proxy: true}},
          %{acp: %{unknown: true}},
          %{permission_mode: "acceptEdits"},
          %{allowed_tools: ["Read", 123]},
          %{turn_timeout_ms: 0},
          %{read_timeout_ms: 0},
          %{stall_timeout_ms: -1}
        ] do
      assert {:error, %Ecto.Changeset{valid?: false}} = CodeBuddyCode.Adapter.validate_options(options)
    end

    for options <- [
          %{http: %{enabled: true}},
          %{transport: "acp_http", http: %{enabled: true, mode: "management"}},
          %{transport: "acp_http", http: %{enabled: true, required: true}},
          %{transport: "acp_http", http: %{enabled: true, allowlist: ["/api/v1/health"]}},
          %{transport: "acp_http", http: %{enabled: true, allowlist: ["GET /api/v1/health"]}},
          %{transport: "acp_http", http: %{enabled: true, allowlist: ["sessions"]}},
          %{transport: "acp_http", http: %{enabled: true, allowlist: ["runs"]}},
          %{transport: "acp_http", http: %{enabled: true, allowlist: ["envs"]}},
          %{transport: "acp_http", http: %{enabled: true, allowlist: ["process"]}},
          %{transport: "acp_http", http: %{enabled: true, allowlist: ["plugins/enable"]}},
          %{transport: "acp_http", http: %{enabled: true, auth_mode: "runtime_gateway"}},
          %{
            transport: "acp_http",
            http: %{enabled: true, auth_mode: "none_for_loopback_smoke", gateway_auth_ref: "credential://gateway/default"}
          }
        ] do
      assert {:error, %Ecto.Changeset{valid?: false}} = CodeBuddyCode.Adapter.validate_options(options)
    end
  end

  test "settings validation allows ACP HTTP loopback transport and rejects out-of-phase combinations" do
    assert :ok =
             CodeBuddyCode.Adapter.validate_options(%{
               transport: "acp_http",
               credential_ref: "credential://codebuddy_code/default",
               http: %{bind_host: "127.0.0.1", port: "auto", auth_mode: "none_for_loopback_smoke"}
             })

    for options <- [
          %{transport: "acp_http", mcp: %{enabled: true}},
          %{transport: "acp_http", http: %{required: true}},
          %{transport: "acp_http", http: %{bind_host: "0.0.0.0"}},
          %{transport: "acp_http", http: %{base_url: "http://127.0.0.1:1234"}},
          %{transport: "acp_http", http: %{gateway_auth_ref: "credential://gateway/default"}},
          %{transport: "acp_http", http: %{auth_mode: "runtime_gateway"}}
        ] do
      assert {:error, %Ecto.Changeset{valid?: false}} = CodeBuddyCode.Adapter.validate_options(options)
    end
  end

  test "settings validation allows explicit CodeBuddy MCP Dynamic Tools only" do
    assert :ok =
             CodeBuddyCode.Adapter.validate_options(%{
               mcp: %{enabled: true, discovery: "explicit_config", approve_generated_server: true}
             })

    assert :ok =
             CodeBuddyCode.Adapter.validate_options(%{
               mcp: %{enabled: true}
             })

    for options <- [
          %{mcp: %{enabled: true, discovery: "project_pointer"}},
          %{mcp: %{enabled: true, allow_project_config_merge: true}},
          %{mcp: %{enabled: true, approve_generated_server: false}},
          %{mcp: %{enabled: true, server_name: "custom_tools"}},
          %{mcp: %{enabled: true, server_name: "bad server"}}
        ] do
      assert {:error, %Ecto.Changeset{valid?: false}} = CodeBuddyCode.Adapter.validate_options(options)
    end
  end

  test "auxiliary HTTP allowlist resolves exact read-only method paths only" do
    assert {:ok, %{method: "GET", path: "/api/v1/health", identifier: "health"}} =
             AuxiliaryHttp.resolve("health")

    assert {:ok, %{method: "GET", path: "/api/v1/info", identifier: "version"}} =
             AuxiliaryHttp.resolve("version")

    for rejected <- [
          "/api/v1/health",
          "GET /api/v1/health",
          "sessions",
          "runs",
          "envs",
          "process",
          "fs",
          "traces",
          "settings",
          "plugins/enable",
          "plugin_mutation"
        ] do
      assert {:error, {:unsupported_auxiliary_http_endpoint, ^rejected}} = AuxiliaryHttp.resolve(rejected)
    end
  end

  test "command renderer selects ACP stdio once and renders baseline controls" do
    settings =
      Settings.from_options(%{
        "command_argv" => ["codebuddy"],
        "allowed_tools" => ["Read"],
        "disallowed_tools" => ["Bash"],
        "model" => "glm-5.1",
        "agent" => "reviewer"
      })

    assert {:ok,
            [
              "codebuddy",
              "--acp",
              "--acp-transport",
              "stdio",
              "--permission-mode",
              "plan",
              "--tools",
              "",
              "--setting-sources",
              "user",
              "--model",
              "glm-5.1",
              "--agent",
              "reviewer",
              "--allowedTools",
              "Read",
              "--disallowedTools",
              "Bash"
            ]} = CommandRenderer.rendered_argv(settings)

    assert {:ok, argv} =
             %{settings | command_argv: ["codebuddy", "--acp", "--acp-transport", "stdio"]}
             |> CommandRenderer.rendered_argv()

    assert Enum.count(argv, &(&1 == "--acp")) == 1
    assert Enum.count(argv, &(&1 == "--acp-transport")) == 1
  end

  test "command renderer gives disallowed tools precedence over allowed tools" do
    settings =
      Settings.from_options(%{
        "command_argv" => ["codebuddy"],
        "allowed_tools" => ["Read", "Bash", "Edit"],
        "disallowed_tools" => ["Bash"]
      })

    assert {:ok, argv} = CommandRenderer.rendered_argv(settings)
    assert option_value(argv, "--allowedTools") == "Read,Edit"
    assert option_value(argv, "--disallowedTools") == "Bash"
  end

  test "command renderer disables user setting sources for managed credentials" do
    settings =
      Settings.from_options(%{
        "command_argv" => ["codebuddy"],
        "credential_ref" => "credential://codebuddy_code/china"
      })

    assert {:ok, argv} = CommandRenderer.rendered_argv(settings)
    assert option_value(argv, "--setting-sources") == ""

    assert {:error, {:codebuddy_command_conflict, "--setting-sources"}} =
             %{settings | command_argv: ["codebuddy", "--setting-sources", "user"]}
             |> CommandRenderer.rendered_argv()
  end

  test "command renderer selects ACP HTTP service mode without stdio ACP flags" do
    settings =
      Settings.from_options(%{
        "transport" => "acp_http",
        "command_argv" => ["codebuddy"],
        "http" => %{"bind_host" => "127.0.0.1", "port" => 49_321},
        "allowed_tools" => ["Read"],
        "disallowed_tools" => ["Bash"],
        "model" => "glm-5.1",
        "agent" => "reviewer"
      })

    assert {:ok, argv} = CommandRenderer.rendered_argv(settings)
    assert ["codebuddy", "--serve", "--host", "127.0.0.1", "--port", "49321" | _rest] = argv
    refute "--acp" in argv
    refute "--acp-transport" in argv
    assert option_value(argv, "--permission-mode") == "plan"
    assert option_value(argv, "--tools") == ""
    assert option_value(argv, "--setting-sources") == "user"
    assert option_value(argv, "--model") == "glm-5.1"
    assert option_value(argv, "--agent") == "reviewer"
    assert option_value(argv, "--allowedTools") == "Read"
    assert option_value(argv, "--disallowedTools") == "Bash"

    assert {:ok, auto_argv} =
             %{settings | http: %{"bind_host" => "127.0.0.1", "port" => "auto"}}
             |> CommandRenderer.rendered_argv()

    refute "--port" in auto_argv
  end

  test "command renderer adds strict MCP config and planned generated tools" do
    settings =
      Settings.from_options(%{
        "command_argv" => ["codebuddy"],
        "permission_mode" => "planned_tools",
        "mcp" => %{"enabled" => true}
      })

    tooling_runtime = %{
      enabled?: true,
      server_name: "symphony_dynamic_tools",
      tool_names: ["repo_checkout"],
      mcp_config_relative_path: ".symphony/codebuddy/sessions/session-1/mcp.json",
      settings_relative_path: ".symphony/codebuddy/sessions/session-1/settings.json"
    }

    assert {:ok, argv} = CommandRenderer.rendered_argv(settings, codebuddy_code_tooling_runtime: tooling_runtime)
    assert option_value(argv, "--mcp-config") == ".symphony/codebuddy/sessions/session-1/mcp.json"
    assert "--strict-mcp-config" in argv
    assert option_value(argv, "--settings") == ".symphony/codebuddy/sessions/session-1/settings.json"
    assert option_value(argv, "--permission-mode") == "plan"
    refute "--tools" in argv
    assert option_value(argv, "--allowedTools") == "mcp__symphony_dynamic_tools__repo_checkout"
    assert option_value(argv, "--setting-sources") == "user"
  end

  test "command renderer rejects conflicting provider-native flags" do
    for argv <- [
          ["codebuddy", "--acp-transport", "streamable-http"],
          ["codebuddy", "--permission-mode", "default"],
          ["codebuddy", "--tools", "Read"],
          ["codebuddy", "--allowedTools", "Read"],
          ["codebuddy", "--disallowedTools", "Bash"],
          ["codebuddy", "--serve"],
          ["codebuddy", "--mcp-config", "mcp.json"],
          ["codebuddy", "--plugin-dir", "plugins"],
          ["codebuddy", "-y"]
        ] do
      assert {:error, {:codebuddy_command_conflict, _flag}} =
               argv
               |> settings_with_argv()
               |> CommandRenderer.rendered_argv()
    end

    for argv <- [
          ["codebuddy", "--serve"],
          ["codebuddy", "--host", "127.0.0.1"],
          ["codebuddy", "--port", "49321"],
          ["codebuddy", "--acp"],
          ["codebuddy", "--acp-transport", "stdio"]
        ] do
      assert {:error, {:codebuddy_command_conflict, _flag}} =
               argv
               |> settings_with_argv("acp_http")
               |> CommandRenderer.rendered_argv()
    end
  end

  test "runtime tooling writes session-scoped MCP config and approval settings" do
    workspace = tmp_workspace("codebuddy-tooling")
    File.mkdir_p!(Path.join(workspace, ".git"))

    settings = Settings.from_options(%{"mcp" => %{"enabled" => true}})

    bridge_env = %{
      SymphonyElixir.Agent.DynamicTool.BridgeContract.base_url_env() => "http://127.0.0.1:4521/api/v1/agent-tools/dynamic",
      SymphonyElixir.Agent.DynamicTool.BridgeContract.token_env() => "session-bridge-token",
      SymphonyElixir.Agent.DynamicTool.BridgeContract.transport_env() => "local_http"
    }

    assert {:ok, runtime} =
             Tooling.write_runtime_mcp_config(
               workspace,
               settings,
               [session_id: "session/with spaces", tool_context: dynamic_tool_context_for_test()],
               bridge_env
             )

    assert runtime.enabled?
    assert runtime.session_id == "session_with_spaces"
    assert runtime.server_name == "symphony_dynamic_tools"
    assert runtime.tool_names == ["fake_dynamic_tool"]

    mcp_config = Jason.decode!(File.read!(Path.join(workspace, runtime.mcp_config_relative_path)))
    server = get_in(mcp_config, ["mcpServers", "symphony_dynamic_tools"])
    assert server["type"] == "stdio"
    assert server["command"] == "node"
    assert server["args"] == [runtime.server_relative_path]
    assert server["env"] == bridge_env
    assert mcp_config["disabledMcpServers"] == []

    codebuddy_settings = Jason.decode!(File.read!(Path.join(workspace, runtime.settings_relative_path)))
    assert codebuddy_settings["enabledMcpjsonServers"] == ["symphony_dynamic_tools"]
    assert get_in(codebuddy_settings, ["permissions", "allow"]) == ["mcp__symphony_dynamic_tools"]

    server_source = File.read!(Path.join(workspace, runtime.server_relative_path))
    assert server_source =~ "fake_dynamic_tool"
    assert server_source =~ "SYMPHONY_DYNAMIC_TOOL_BRIDGE_BASE_URL"
    refute server_source =~ "session-bridge-token"

    manifest = Jason.decode!(File.read!(Path.join([workspace, ".symphony", "codebuddy", "manifest.json"])))

    assert get_in(manifest, ["sessions", Access.at(0), "files"]) == [
             runtime.mcp_config_relative_path,
             runtime.settings_relative_path,
             runtime.server_relative_path
           ]

    assert File.read!(Path.join([workspace, ".git", "info", "exclude"])) =~ ".symphony/\n"

    assert {:ok, empty_runtime} =
             Tooling.write_runtime_mcp_config(
               workspace,
               settings,
               [session_id: "session/with spaces", tool_context: empty_dynamic_tool_context_for_test()],
               %{}
             )

    refute empty_runtime.enabled?

    assert Jason.decode!(File.read!(Path.join(workspace, empty_runtime.mcp_config_relative_path))) == %{
             "mcpServers" => %{},
             "disabledMcpServers" => []
           }

    refute File.exists?(Path.join(workspace, empty_runtime.server_relative_path))
  end

  test "fake ACP provider starts, handshakes, streams one turn, and stops" do
    workspace = tmp_workspace("codebuddy-success")
    script = write_fake_acp_script!(workspace, :success)

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: fake_acp_options(script)
      })

    assert {:ok, session} = AgentProvider.start_session(workspace, agent_provider_config: config, run_id: "run-codebuddy")
    assert session.agent_provider_kind == @provider_kind
    assert session.session_id == "codebuddy-session-1"
    assert session.thread_id == "codebuddy-session-1"

    assert {:ok,
            %TurnResult{
              status: :completed,
              session_id: "codebuddy-session-1",
              thread_id: "codebuddy-session-1",
              turn_id: "codebuddy-user-message-1",
              usage: %{}
            }} =
             AgentProvider.run_turn(
               session,
               "Reply with exactly pong",
               %{id: "issue-1", identifier: "MEM-1"},
               on_message: fn message -> send(self(), {:codebuddy_message, message}) end
             )

    assert_receive {:codebuddy_message, %{event: "message.part.updated"} = message}
    assert AgentProvider.present_message(message, kind: @provider_kind) == "agent message streaming: pong"
    assert :ok = AgentProvider.stop_session(session)
  end

  test "fake ACP provider validates configured model against session metadata" do
    workspace = tmp_workspace("codebuddy-model-match")
    script = write_fake_acp_script!(workspace, :success)

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: Map.put(fake_acp_options(script), :model, "glm-5.1")
      })

    assert {:ok, session} = AgentProvider.start_session(workspace, agent_provider_config: config, run_id: "run-codebuddy-model-match")
    assert get_in(session.provider_state, [:provider_metadata, "session", "currentModelId"]) == "glm-5.1"
    assert :ok = AgentProvider.stop_session(session)
  end

  test "fake ACP provider fails clearly when configured model does not match session metadata" do
    workspace = tmp_workspace("codebuddy-model-mismatch")
    script = write_fake_acp_script!(workspace, :available_model_success)

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: Map.put(fake_acp_options(script), :model, "not-a-codebuddy-model")
      })

    assert {:error,
            %Error{
              provider: @provider_kind,
              operation: :start_session,
              code: :agent_provider_config_invalid,
              retryable?: false,
              details: %{
                configured_model: "not-a-codebuddy-model",
                current_model: "glm-5.1",
                available_models: ["glm-5.1", "glm-5.1-pro"]
              }
            } = error} =
             AgentProvider.start_session(workspace, agent_provider_config: config, run_id: "run-codebuddy-model-mismatch")

    assert error.message =~ "configured model is not supported"
  end

  test "fake ACP provider treats zero exit during prompt as completed turn" do
    workspace = tmp_workspace("codebuddy-exit-zero")
    script = write_fake_acp_script!(workspace, :success_exit_zero_after_prompt)

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: fake_acp_options(script)
      })

    assert {:ok, session} = AgentProvider.start_session(workspace, agent_provider_config: config, run_id: "run-codebuddy-exit-zero")

    assert {:ok,
            %TurnResult{
              status: :completed,
              session_id: "codebuddy-session-1",
              thread_id: "codebuddy-session-1",
              turn_id: nil,
              metadata: %{
                "provider_result" => %{
                  "stopReason" => "end_turn",
                  "_meta" => %{"codebuddy.ai/finishReason" => "stop"}
                }
              }
            }} =
             AgentProvider.run_turn(
               session,
               "Reply with exactly pong",
               %{id: "issue-1", identifier: "MEM-1"},
               on_message: fn message -> send(self(), {:codebuddy_message, message}) end
             )

    assert_receive {:codebuddy_message, %{event: "message.part.updated"} = message}
    assert AgentProvider.present_message(message, kind: @provider_kind) == "agent message streaming: pong"
    assert :ok = AgentProvider.stop_session(session)
  end

  test "fake ACP provider stop terminates spawned MCP-style child process" do
    workspace = tmp_workspace("codebuddy-child-cleanup")
    script = write_fake_acp_script!(workspace, :success_with_child)
    child_pid_file = Path.join(workspace, "codebuddy_child.pid")

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: fake_acp_options(script)
      })

    assert {:ok, session} = AgentProvider.start_session(workspace, agent_provider_config: config, run_id: "run-codebuddy-child-cleanup")

    child_pid = wait_for_pid_file!(child_pid_file)
    assert PlatformProcess.os_process_alive?(child_pid)

    assert :ok = AgentProvider.stop_session(session)
    refute wait_for_os_process_alive?(child_pid)
  end

  test "fake ACP provider starts with managed CodeBuddy API-key credential" do
    workspace = tmp_workspace("codebuddy-managed-credential")
    script = write_fake_acp_script!(workspace, :record_argv_success)
    credential_settings = %{enabled: true, store_root: Path.join(workspace, "agent_credentials")}

    assert {:ok, account} =
             Store.create_or_update(
               @provider_kind,
               "china",
               [credential_kind: CredentialEnv.env_token_credential_kind(), internet_environment: "internal"],
               credential_settings
             )

    File.write!(account.secret_file, "ck-managed-test\n")

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: Map.merge(fake_acp_options(script), %{credential_ref: Store.credential_ref(account)})
      })

    assert {:ok, session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               agent_credentials: credential_settings,
               run_id: "run-codebuddy-managed"
             )

    args = File.read!(Path.join(workspace, "codebuddy_args.txt")) |> String.split("\n", trim: false)
    assert option_value(args, "--setting-sources") == ""
    assert session.agent_credential_lease.account_id == "china"

    assert File.read!(Path.join(workspace, "codebuddy_api_key.txt")) == "ck-managed-test\n"
    assert File.read!(Path.join(workspace, "codebuddy_internet_environment.txt")) == "internal\n"
    assert File.read!(Path.join(workspace, "codebuddy_auth_token.txt")) == "\n"
    assert File.read!(Path.join(workspace, "codebuddy_base_url.txt")) == "\n"

    assert :ok = AgentProvider.stop_session(session, agent_credentials: credential_settings)
  end

  test "fake ACP HTTP provider connects, handshakes, streams one turn, and cleans up" do
    workspace = tmp_workspace("codebuddy-http-success")

    {base_url, request_log} =
      start_codebuddy_http_test_server!(
        health_status: 401,
        health_body: %{"code" => "AUTH_REQUIRED", "message" => "auth required"}
      )

    port = base_url |> URI.parse() |> Map.fetch!(:port)
    script = write_fake_acp_http_launcher_script!(workspace, port)

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: %{
          transport: "acp_http",
          command_argv: [script],
          http: %{bind_host: "127.0.0.1", port: "auto", auth_mode: "none_for_loopback_smoke"},
          read_timeout_ms: @acp_http_auto_port_startup_timeout_ms,
          turn_timeout_ms: 2_000,
          stall_timeout_ms: 1_000
        }
      })

    assert {:ok, session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               run_id: "run-codebuddy-http"
             )

    args = File.read!(Path.join(workspace, "codebuddy_http_args.txt")) |> String.split("\n", trim: true)
    assert option_value(args, "--host") == "127.0.0.1"
    refute "--port" in args
    refute "--acp" in args
    refute "--acp-transport" in args

    assert session.agent_provider_kind == @provider_kind
    assert session.session_id == "codebuddy-http-session-1"
    assert session.thread_id == "codebuddy-http-session-1"
    assert session.metadata[:acp_http_base_url] == base_url
    refute inspect(session.metadata) =~ "test-session-token"

    assert {:ok,
            %TurnResult{
              status: :completed,
              session_id: "codebuddy-http-session-1",
              thread_id: "codebuddy-http-session-1",
              turn_id: "codebuddy-http-user-message-1",
              usage: %{}
            }} =
             AgentProvider.run_turn(
               session,
               "Reply with exactly pong",
               %{id: "issue-1", identifier: "MEM-1"},
               on_message: fn message -> send(self(), {:codebuddy_http_message, message}) end
             )

    assert_receive {:codebuddy_http_message, %{event: "message.part.updated"} = message}
    assert AgentProvider.present_message(message, kind: @provider_kind) == "agent message streaming: pong over http"
    assert :ok = AgentProvider.stop_session(session)

    requests = Agent.get(request_log, & &1)
    refute Enum.any?(requests, &match?(%{method: "GET", path: "/api/v1/health"}, &1))
    assert Enum.any?(requests, &match?(%{method: "POST", path: "/api/v1/acp/connect", codebuddy_request: ["1"]}, &1))

    assert %{
             accept: [accept],
             authorization: ["Bearer test-session-token"],
             acp_connection_id: ["test-connection-id"],
             codebuddy_request: ["1"]
           } =
             Enum.find(requests, fn request ->
               request.method == "POST" and request.path == "/api/v1/acp" and request.body =~ "session/prompt"
             end)

    assert accept =~ "application/json"
    assert accept =~ "text/event-stream"
    assert Enum.any?(requests, &match?(%{method: "DELETE", path: "/api/v1/acp"}, &1))
  end

  test "fake ACP HTTP provider sends session cancel notification on prompt start timeout" do
    workspace = tmp_workspace("codebuddy-http-cancel")
    {base_url, request_log} = start_codebuddy_http_test_server!(prompt_delay_ms: 1_000)
    port = base_url |> URI.parse() |> Map.fetch!(:port)
    script = write_fake_acp_http_launcher_script!(workspace, port)

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: %{
          transport: "acp_http",
          command_argv: [script],
          http: %{bind_host: "127.0.0.1", port: port, auth_mode: "none_for_loopback_smoke"},
          read_timeout_ms: 300,
          turn_timeout_ms: 700,
          stall_timeout_ms: 200
        }
      })

    assert {:ok, session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               run_id: "run-codebuddy-http-cancel"
             )

    assert {:error,
            %Error{
              provider: @provider_kind,
              operation: :run_turn,
              code: :agent_provider_response_timeout,
              retryable?: true
            }} =
             AgentProvider.run_turn(
               session,
               "Wait long enough to trigger cancellation",
               %{id: "issue-1", identifier: "MEM-1"}
             )

    assert :ok = AgentProvider.stop_session(session)

    requests = Agent.get(request_log, & &1)

    assert Enum.any?(requests, fn request ->
             request.method == "POST" and request.path == "/api/v1/acp" and request.body =~ "session/cancel" and
               request.authorization == ["Bearer test-session-token"]
           end)
  end

  test "fake ACP HTTP provider starts with managed CodeBuddy API-key credential" do
    workspace = tmp_workspace("codebuddy-http-managed")
    {base_url, request_log} = start_codebuddy_http_test_server!(health_status: 401, health_body: %{"code" => "AUTH_REQUIRED"})
    port = base_url |> URI.parse() |> Map.fetch!(:port)
    script = write_fake_acp_http_launcher_script!(workspace, port)
    credential_settings = %{enabled: true, store_root: Path.join(workspace, "agent_credentials")}

    assert {:ok, account} =
             Store.create_or_update(
               @provider_kind,
               "china",
               [credential_kind: CredentialEnv.env_token_credential_kind(), internet_environment: "internal"],
               credential_settings
             )

    File.write!(account.secret_file, "ck-managed-http-test\n")

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: %{
          transport: "acp_http",
          command_argv: [script],
          credential_ref: Store.credential_ref(account),
          http: %{bind_host: "127.0.0.1", port: "auto", auth_mode: "none_for_loopback_smoke"},
          read_timeout_ms: @acp_http_auto_port_startup_timeout_ms,
          turn_timeout_ms: 2_000,
          stall_timeout_ms: 1_000
        }
      })

    assert {:ok, session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               agent_credentials: credential_settings,
               run_id: "run-codebuddy-http-managed"
             )

    args = File.read!(Path.join(workspace, "codebuddy_http_args.txt")) |> String.split("\n", trim: false)
    assert option_value(args, "--setting-sources") == ""
    assert session.agent_credential_lease.account_id == "china"
    refute inspect(session.metadata) =~ "test-session-token"

    assert File.read!(Path.join(workspace, "codebuddy_api_key.txt")) == "ck-managed-http-test\n"
    assert File.read!(Path.join(workspace, "codebuddy_internet_environment.txt")) == "internal\n"
    assert File.read!(Path.join(workspace, "codebuddy_auth_token.txt")) == "\n"
    assert File.read!(Path.join(workspace, "codebuddy_base_url.txt")) == "\n"

    assert :ok = AgentProvider.stop_session(session, agent_credentials: credential_settings)

    requests = Agent.get(request_log, & &1)
    refute Enum.any?(requests, &match?(%{method: "GET", path: "/api/v1/health"}, &1))
    assert Enum.any?(requests, &match?(%{method: "POST", path: "/api/v1/acp/connect", codebuddy_request: ["1"]}, &1))
  end

  test "auxiliary HTTP metadata collection projects allowlisted fields after ACP HTTP turn" do
    workspace = tmp_workspace("codebuddy-aux-http")
    {base_url, request_log} = start_codebuddy_http_test_server!([])
    port = base_url |> URI.parse() |> Map.fetch!(:port)
    script = write_fake_acp_http_launcher_script!(workspace, port)

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: %{
          transport: "acp_http",
          command_argv: [script],
          http: %{
            enabled: true,
            bind_host: "127.0.0.1",
            port: port,
            auth_mode: "none_for_loopback_smoke",
            allowlist: ["health", "version", "metrics_summary", "session_stats", "plugin_inventory"]
          },
          read_timeout_ms: @acp_http_read_timeout_ms,
          turn_timeout_ms: 2_000,
          stall_timeout_ms: 1_000
        }
      })

    assert {:ok, session} = AgentProvider.start_session(workspace, agent_provider_config: config, run_id: "run-codebuddy-aux-http")

    assert {:ok, %TurnResult{status: :completed, usage: %{}, metadata: metadata}} =
             AgentProvider.run_turn(session, "Reply with exactly pong", %{id: "issue-1", identifier: "MEM-1"})

    assert :ok = AgentProvider.stop_session(session)

    auxiliary = Map.fetch!(metadata, "auxiliary_http")
    assert get_in(auxiliary, ["health", "status"]) == "ok"
    assert get_in(auxiliary, ["version", "version"]) == "2.97.2"
    assert get_in(auxiliary, ["version", "nodeVersion"]) == "v22.17.0"
    assert get_in(auxiliary, ["metrics_summary", "instance_count"]) == 1
    assert get_in(auxiliary, ["session_stats", "tokenUsageByModel"]) == %{"present" => true, "model_count" => 1}
    assert get_in(auxiliary, ["plugin_inventory", Access.at(0), "name"]) == "Safe Plugin"

    refute Map.has_key?(auxiliary["version"], "cwd")
    refute Map.has_key?(auxiliary["version"], "tunnelUrl")
    refute Map.has_key?(auxiliary["version"], "userName")
    refute Map.has_key?(auxiliary["metrics_summary"], "instances")
    refute inspect(auxiliary) =~ "redacted-path"
    refute inspect(auxiliary) =~ "redacted prompt"
    refute inspect(auxiliary) =~ "input_tokens"
    refute inspect(auxiliary) =~ "hookBody"

    requests = Agent.get(request_log, & &1)

    for path <- ["/api/v1/health", "/api/v1/info", "/api/v1/metrics", "/api/v1/stats/session", "/api/v1/plugins"] do
      assert Enum.any?(requests, &match?(%{method: "GET", path: ^path, codebuddy_request: ["1"]}, &1))
    end

    refute Enum.any?(requests, &(&1.path in ["/api/v1/sessions", "/api/v1/runs", "/api/v1/envs", "/api/v1/process/list"]))
  end

  test "auxiliary HTTP optional failures do not fail a completed ACP HTTP turn" do
    workspace = tmp_workspace("codebuddy-aux-http-optional-failure")
    {base_url, _request_log} = start_codebuddy_http_test_server!(health_status: 500, health_body: %{"error" => %{"code" => "BROKEN"}})
    port = base_url |> URI.parse() |> Map.fetch!(:port)
    script = write_fake_acp_http_launcher_script!(workspace, port)

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: %{
          transport: "acp_http",
          command_argv: [script],
          http: %{enabled: true, bind_host: "127.0.0.1", port: port, auth_mode: "none_for_loopback_smoke", allowlist: ["health"]},
          read_timeout_ms: @acp_http_read_timeout_ms,
          turn_timeout_ms: 2_000,
          stall_timeout_ms: 1_000
        }
      })

    assert {:ok, session} = AgentProvider.start_session(workspace, agent_provider_config: config, run_id: "run-codebuddy-aux-http-failure")

    assert {:ok, %TurnResult{status: :completed, usage: %{}, metadata: %{"auxiliary_http" => auxiliary}}} =
             AgentProvider.run_turn(session, "Reply with exactly pong", %{id: "issue-1", identifier: "MEM-1"})

    assert get_in(auxiliary, ["errors", Access.at(0), "identifier"]) == "health"
    assert get_in(auxiliary, ["errors", Access.at(0), "response_status"]) == 500
    assert :ok = AgentProvider.stop_session(session)
  end

  test "auxiliary HTTP runtime gateway auth uses bearer header and redacts credential material" do
    workspace = tmp_workspace("codebuddy-aux-http-gateway-auth")
    {base_url, request_log} = start_codebuddy_http_test_server!(gateway_phrase: "local-gateway-fixture")
    port = base_url |> URI.parse() |> Map.fetch!(:port)
    script = write_fake_acp_http_launcher_script!(workspace, port)

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: %{
          transport: "acp_http",
          command_argv: [script],
          http: %{
            enabled: true,
            bind_host: "127.0.0.1",
            port: port,
            auth_mode: "runtime_gateway",
            gateway_auth_ref: "credential://gateway/codebuddy-local",
            allowlist: ["health"]
          },
          read_timeout_ms: @acp_http_read_timeout_ms,
          turn_timeout_ms: 2_000,
          stall_timeout_ms: 1_000
        }
      })

    assert {:ok, session} = AgentProvider.start_session(workspace, agent_provider_config: config, run_id: "run-codebuddy-aux-http-auth")

    assert {:ok, %TurnResult{status: :completed, metadata: %{"auxiliary_http" => auxiliary}}} =
             AgentProvider.run_turn(
               session,
               "Reply with exactly pong",
               %{id: "issue-1", identifier: "MEM-1"},
               codebuddy_auxiliary_http_gateway_auth: %{bearer: "local-gateway-fixture"}
             )

    assert get_in(auxiliary, ["health", "status"]) == "ok"
    refute inspect(auxiliary) =~ "local-gateway-fixture"
    assert :ok = AgentProvider.stop_session(session)

    requests = Agent.get(request_log, & &1)

    assert Enum.any?(requests, fn request ->
             request.method == "GET" and request.path == "/api/v1/health" and
               request.authorization == ["Bearer local-gateway-fixture"] and request.query_string == ""
           end)

    refute Enum.any?(requests, &String.contains?(&1.query_string, "password"))
  end

  test "auxiliary HTTP runtime gateway auth resolves gateway_auth_ref credential material" do
    workspace = tmp_workspace("codebuddy-aux-http-gateway-ref")
    gateway_phrase = "local-gateway-ref-fixture"
    credential_settings = %{enabled: true, store_root: Path.join(workspace, "agent_credentials")}
    {base_url, request_log} = start_codebuddy_http_test_server!(gateway_phrase: gateway_phrase)
    port = base_url |> URI.parse() |> Map.fetch!(:port)
    script = write_fake_acp_http_launcher_script!(workspace, port)

    assert {:ok, gateway_account} = Store.create_or_update("gateway", "codebuddy-local", [], credential_settings)
    File.write!(gateway_account.secret_file, gateway_phrase <> "\n")

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: %{
          transport: "acp_http",
          command_argv: [script],
          http: %{
            enabled: true,
            bind_host: "127.0.0.1",
            port: port,
            auth_mode: "runtime_gateway",
            gateway_auth_ref: Store.credential_ref(gateway_account),
            allowlist: ["health"]
          },
          read_timeout_ms: @acp_http_read_timeout_ms,
          turn_timeout_ms: 2_000,
          stall_timeout_ms: 1_000
        }
      })

    assert {:ok, session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               agent_credentials: credential_settings,
               run_id: "run-codebuddy-aux-http-auth-ref"
             )

    assert {:ok, %TurnResult{status: :completed, usage: %{}, metadata: %{"auxiliary_http" => auxiliary} = metadata}} =
             AgentProvider.run_turn(
               session,
               "Reply with exactly pong",
               %{id: "issue-1", identifier: "MEM-1"},
               agent_credentials: credential_settings
             )

    assert get_in(auxiliary, ["health", "status"]) == "ok"
    refute inspect(metadata) =~ gateway_phrase
    assert :ok = AgentProvider.stop_session(session, agent_credentials: credential_settings)

    requests = Agent.get(request_log, & &1)

    assert Enum.any?(requests, fn request ->
             request.method == "GET" and request.path == "/api/v1/health" and
               request.authorization == ["Bearer " <> gateway_phrase] and request.query_string == ""
           end)

    refute Enum.any?(requests, &String.contains?(&1.query_string, "password"))
    assert {:ok, lease} = Store.acquire("gateway", Store.credential_ref(gateway_account), agent_credentials: credential_settings)
    assert :ok = Store.release(lease, agent_credentials: credential_settings)
  end

  test "auxiliary HTTP missing gateway_auth_ref material is bounded metadata and does not fail turn" do
    workspace = tmp_workspace("codebuddy-aux-http-gateway-ref-missing")
    credential_settings = %{enabled: true, store_root: Path.join(workspace, "agent_credentials")}
    {base_url, request_log} = start_codebuddy_http_test_server!(gateway_phrase: "unavailable-gateway-phrase")
    port = base_url |> URI.parse() |> Map.fetch!(:port)
    script = write_fake_acp_http_launcher_script!(workspace, port)

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: %{
          transport: "acp_http",
          command_argv: [script],
          http: %{
            enabled: true,
            bind_host: "127.0.0.1",
            port: port,
            auth_mode: "runtime_gateway",
            gateway_auth_ref: "credential://gateway/missing",
            allowlist: ["health"]
          },
          read_timeout_ms: @acp_http_read_timeout_ms,
          turn_timeout_ms: 2_000,
          stall_timeout_ms: 1_000
        }
      })

    assert {:ok, session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               agent_credentials: credential_settings,
               run_id: "run-codebuddy-aux-http-auth-ref-missing"
             )

    assert {:ok, %TurnResult{status: :completed, usage: %{}, metadata: %{"auxiliary_http" => auxiliary} = metadata}} =
             AgentProvider.run_turn(
               session,
               "Reply with exactly pong",
               %{id: "issue-1", identifier: "MEM-1"},
               agent_credentials: credential_settings
             )

    assert get_in(auxiliary, ["errors", Access.at(0), "identifier"]) == "gateway_auth"
    assert get_in(auxiliary, ["errors", Access.at(0), "reason"]) =~ "gateway auth credential unavailable"
    refute inspect(metadata) =~ "unavailable-gateway-phrase"
    assert :ok = AgentProvider.stop_session(session, agent_credentials: credential_settings)

    requests = Agent.get(request_log, & &1)
    refute Enum.any?(requests, &(&1.method == "GET" and &1.path == "/api/v1/health"))
    refute Enum.any?(requests, &String.contains?(&1.query_string, "password"))
  end

  test "fake ACP provider launches with generated MCP dynamic tool config" do
    workspace = tmp_workspace("codebuddy-dynamic-tools")
    script = write_fake_acp_script!(workspace, :record_argv_success)

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: Map.merge(fake_acp_options(script), %{permission_mode: "planned_tools", mcp: %{enabled: true}})
      })

    assert {:ok, session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               run_id: "run-codebuddy-dynamic",
               tool_context: dynamic_tool_context_for_test(),
               dynamic_tool_exposure: :all,
               http_port: 4521
             )

    args = File.read!(Path.join(workspace, "codebuddy_args.txt")) |> String.split("\n", trim: true)
    assert option_value(args, "--mcp-config") =~ ".symphony/codebuddy/sessions/"
    assert "--strict-mcp-config" in args
    assert option_value(args, "--settings") =~ ".symphony/codebuddy/sessions/"
    assert option_value(args, "--allowedTools") == "mcp__symphony_dynamic_tools__fake_dynamic_tool"
    refute "--plugin-dir" in args
    refute "--serve" in args

    mcp_config_path = Path.join(workspace, option_value(args, "--mcp-config"))
    settings_path = Path.join(workspace, option_value(args, "--settings"))
    assert File.exists?(mcp_config_path)
    assert File.exists?(settings_path)

    mcp_config = Jason.decode!(File.read!(mcp_config_path))
    assert get_in(mcp_config, ["mcpServers", "symphony_dynamic_tools", "env", SymphonyElixir.Agent.DynamicTool.BridgeContract.transport_env()]) == "local_http"
    assert get_in(Jason.decode!(File.read!(settings_path)), ["permissions", "allow"]) == ["mcp__symphony_dynamic_tools"]

    assert File.read!(Path.join(workspace, "dynamic_tool_bridge_base_url.txt")) ==
             "http://127.0.0.1:4521/api/v1/agent-tools/dynamic\n"

    assert File.read!(Path.join(workspace, "dynamic_tool_bridge_transport.txt")) == "local_http\n"
    assert session.metadata[:dynamic_tool_bridge_transport] == "local_http"
    assert get_in(session.provider_state.provider_metadata, ["dynamic_tools", :tool_count]) == 1

    assert :ok = AgentProvider.stop_session(session)
  end

  test "fake ACP provider isolates generated MCP config from repository-authored MCP and plugin files" do
    workspace = tmp_workspace("codebuddy-dynamic-tools-isolation")
    write_repository_authored_codebuddy_files!(workspace)
    script = write_fake_acp_script!(workspace, :record_argv_success)

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: Map.merge(fake_acp_options(script), %{permission_mode: "planned_tools", mcp: %{enabled: true}})
      })

    assert {:ok, session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               run_id: "run-codebuddy-dynamic-isolation",
               tool_context: dynamic_tool_context_for_test(),
               dynamic_tool_exposure: :all,
               http_port: unique_http_port()
             )

    args = File.read!(Path.join(workspace, "codebuddy_args.txt")) |> String.split("\n", trim: true)
    rendered = Enum.join(args, "\n")

    mcp_config_arg = option_value(args, "--mcp-config")
    settings_arg = option_value(args, "--settings")

    assert mcp_config_arg =~ ".symphony/codebuddy/sessions/"
    assert settings_arg =~ ".symphony/codebuddy/sessions/"
    assert "--strict-mcp-config" in args
    assert option_value(args, "--allowedTools") == "mcp__symphony_dynamic_tools__fake_dynamic_tool"

    refute "--plugin-dir" in args
    refute rendered =~ ".mcp.json"
    refute rendered =~ "\nmcp.json"
    refute rendered =~ ".codebuddy/settings.json"
    refute rendered =~ ".codebuddy/plugins"
    refute rendered =~ "plugins/repo-plugin"

    mcp_config = Jason.decode!(File.read!(Path.join(workspace, mcp_config_arg)))
    assert Map.keys(mcp_config["mcpServers"]) == ["symphony_dynamic_tools"]
    refute inspect(mcp_config) =~ "repo_authored"
    refute inspect(mcp_config) =~ "repo_plugin"

    codebuddy_settings = Jason.decode!(File.read!(Path.join(workspace, settings_arg)))

    assert codebuddy_settings == %{
             "enabledMcpjsonServers" => ["symphony_dynamic_tools"],
             "permissions" => %{"allow" => ["mcp__symphony_dynamic_tools"]}
           }

    refute Map.has_key?(codebuddy_settings, "enableAllProjectMcpServers")
    refute Map.has_key?(codebuddy_settings, "enabledPlugins")

    assert :ok = AgentProvider.stop_session(session)
  end

  test "stale generated session files cannot expose removed dynamic tools" do
    workspace = tmp_workspace("codebuddy-stale-dynamic-tools")
    old_session_dir = Path.join([workspace, ".symphony", "codebuddy", "sessions", "old-session"])
    File.mkdir_p!(old_session_dir)
    File.write!(Path.join(old_session_dir, "planned_tools_mcp.js"), "stale_dynamic_tool")

    File.write!(
      Path.join(old_session_dir, "mcp.json"),
      Jason.encode!(%{
        "mcpServers" => %{
          "symphony_dynamic_tools" => %{
            "type" => "stdio",
            "command" => "node",
            "args" => [".symphony/codebuddy/sessions/old-session/planned_tools_mcp.js"]
          }
        }
      })
    )

    settings =
      Settings.from_options(%{
        "command_argv" => ["codebuddy"],
        "permission_mode" => "planned_tools",
        "mcp" => %{"enabled" => true}
      })

    assert {:ok, runtime} =
             Tooling.write_runtime_mcp_config(
               workspace,
               settings,
               [session_id: "new-session", tool_context: dynamic_tool_context_for_test()],
               %{}
             )

    assert runtime.session_id == "new-session"
    assert runtime.tool_names == ["fake_dynamic_tool"]

    assert {:ok, argv} =
             CommandRenderer.rendered_argv(settings, codebuddy_code_tooling_runtime: runtime)

    rendered = Enum.join(argv, "\n")
    assert option_value(argv, "--mcp-config") == ".symphony/codebuddy/sessions/new-session/mcp.json"
    assert option_value(argv, "--settings") == ".symphony/codebuddy/sessions/new-session/settings.json"
    assert option_value(argv, "--allowedTools") == "mcp__symphony_dynamic_tools__fake_dynamic_tool"
    refute rendered =~ "old-session"
    refute rendered =~ "stale_dynamic_tool"

    current_mcp_config = File.read!(Path.join(workspace, runtime.mcp_config_relative_path))
    current_settings = File.read!(Path.join(workspace, runtime.settings_relative_path))
    current_server = File.read!(Path.join(workspace, runtime.server_relative_path))

    assert current_mcp_config =~ "new-session/planned_tools_mcp.js"
    refute current_mcp_config =~ "old-session"
    refute current_settings =~ "stale_dynamic_tool"
    refute current_server =~ "stale_dynamic_tool"

    manifest = Jason.decode!(File.read!(Path.join([workspace, ".symphony", "codebuddy", "manifest.json"])))
    assert get_in(manifest, ["sessions", Access.at(0), "session_id"]) == "new-session"
    assert get_in(manifest, ["sessions", Access.at(0), "tool_names"]) == ["fake_dynamic_tool"]
  end

  test "permission requests become input-required errors in unattended baseline" do
    workspace = tmp_workspace("codebuddy-permission")
    script = write_fake_acp_script!(workspace, :permission_request)

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: fake_acp_options(script)
      })

    assert {:ok, session} = AgentProvider.start_session(workspace, agent_provider_config: config, run_id: "run-codebuddy-permission")

    assert {:error,
            %Error{
              provider: @provider_kind,
              operation: :run_turn,
              code: :agent_provider_input_required,
              retryable?: false
            }} =
             AgentProvider.run_turn(
               session,
               "Read package.json",
               %{id: "issue-1", identifier: "MEM-1"},
               on_message: fn message -> send(self(), {:codebuddy_message, message}) end
             )

    assert_receive {:codebuddy_message, %{event: :turn_input_required}}
    assert :ok = AgentProvider.stop_session(session)
  end

  test "permission requests are auto-selected in explicit bypass mode" do
    workspace = tmp_workspace("codebuddy-permission-bypass")
    script = write_fake_acp_script!(workspace, :permission_request_then_success)

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: Map.merge(fake_acp_options(script), %{permission_mode: "bypass_permissions"})
      })

    assert {:ok, session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               run_id: "run-codebuddy-permission-bypass"
             )

    assert {:ok, result} =
             AgentProvider.run_turn(
               session,
               "Run git status",
               %{id: "issue-1", identifier: "MEM-1"},
               on_message: fn message -> send(self(), {:codebuddy_message, message}) end
             )

    assert result.status == :completed
    assert get_in(result.metadata, [:result, "stopReason"]) == "end_turn"
    refute_receive {:codebuddy_message, %{event: :turn_input_required}}, 100

    response = workspace |> Path.join("permission_response.json") |> File.read!() |> Jason.decode!()
    assert get_in(response, ["result", "outcome", "outcome"]) == "selected"
    assert get_in(response, ["result", "outcome", "optionId"]) == "allow_always"

    assert :ok = AgentProvider.stop_session(session)
  end

  test "non-MVP runtime capabilities return explicit unsupported errors before provider launch" do
    workspace = tmp_workspace("codebuddy-unsupported")

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: %{command_argv: ["/bin/echo"]}
      })

    assert {:error,
            %Error{
              provider: @provider_kind,
              operation: :start_session,
              code: :agent_provider_remote_unsupported,
              retryable?: false
            }} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               worker_host: "worker.example",
               run_id: "run-codebuddy-remote"
             )

    for {options, expected_error_fragment} <- [
          {%{plugin: %{enabled: true}}, "CodeBuddy plugins are unsupported"},
          {%{telemetry: %{enabled: true}}, "telemetry is unsupported"},
          {%{quota_probe: %{enabled: true}}, "unsupported option"},
          {%{acp: %{client_file_proxy: true}}, "ACP file proxy is unsupported"},
          {%{acp: %{client_terminal_proxy: true}}, "ACP terminal proxy is unsupported"}
        ] do
      rejected_config =
        ProviderConfig.new(%{
          kind: @provider_kind,
          options: Map.merge(%{command_argv: ["/bin/echo"]}, options)
        })

      assert {:error,
              %Error{
                provider: @provider_kind,
                operation: :start_session,
                code: :agent_provider_config_invalid,
                retryable?: false,
                details: %{validation_errors: validation_errors}
              }} =
               AgentProvider.start_session(workspace,
                 agent_provider_config: rejected_config,
                 run_id: "run-codebuddy-invalid-phase-one-option"
               )

      assert validation_errors =~ expected_error_fragment
    end

    assert {:error,
            %Error{
              provider: @provider_kind,
              operation: :start_session,
              code: :agent_provider_quota_unavailable,
              retryable?: false
            }} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               run_id: "run-codebuddy-quota",
               agent_quota_preflight: :required
             )
  end

  defp settings_with_argv(argv), do: settings_with_argv(argv, "acp_stdio")
  defp settings_with_argv(argv, transport), do: Settings.from_options(%{"command_argv" => argv, "transport" => transport})

  defp fake_acp_options(script) do
    %{
      command_argv: [script],
      acp: %{"handshake_timeout_ms" => 3_000},
      read_timeout_ms: @acp_stdio_read_timeout_ms,
      turn_timeout_ms: 2_000,
      stall_timeout_ms: 1_000
    }
  end

  defp option_value(argv, flag) do
    argv
    |> Enum.with_index()
    |> Enum.find_value(fn
      {^flag, index} -> Enum.at(argv, index + 1)
      {arg, _index} -> if String.starts_with?(arg, flag <> "="), do: String.replace_prefix(arg, flag <> "=", ""), else: nil
    end)
  end

  defp tmp_workspace(prefix) do
    workspace = Path.join(System.tmp_dir!(), "symphony-#{prefix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)
    workspace
  end

  defp unique_http_port, do: 46_000 + rem(System.unique_integer([:positive]), 1_000)

  defp wait_for_pid_file!(path, attempts_remaining \\ 40)

  defp wait_for_pid_file!(path, attempts_remaining) when attempts_remaining > 0 do
    case File.read(path) do
      {:ok, contents} ->
        case Integer.parse(String.trim(contents)) do
          {pid, ""} when pid > 0 -> pid
          _other -> retry_pid_file(path, attempts_remaining)
        end

      {:error, _reason} ->
        retry_pid_file(path, attempts_remaining)
    end
  end

  defp wait_for_pid_file!(_path, 0), do: flunk("pid file was not written")

  defp retry_pid_file(path, attempts_remaining) do
    Process.sleep(25)
    wait_for_pid_file!(path, attempts_remaining - 1)
  end

  defp wait_for_os_process_alive?(os_pid, attempts_remaining \\ 40)

  defp wait_for_os_process_alive?(os_pid, attempts_remaining) when attempts_remaining > 0 do
    if PlatformProcess.os_process_alive?(os_pid) do
      Process.sleep(25)
      wait_for_os_process_alive?(os_pid, attempts_remaining - 1)
    else
      false
    end
  end

  defp wait_for_os_process_alive?(_os_pid, 0), do: true

  defp start_codebuddy_http_test_server!(opts) do
    {:ok, request_log} = Agent.start_link(fn -> [] end)

    pid =
      start_supervised!({Bandit, plug: {CodeBuddyHttpTestPlug, Keyword.merge([owner: self(), request_log: request_log], opts)}, scheme: :http, port: 0, ip: {127, 0, 0, 1}})

    {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(pid)
    {"http://127.0.0.1:#{port}", request_log}
  end

  defp write_repository_authored_codebuddy_files!(workspace) do
    File.write!(
      Path.join(workspace, ".mcp.json"),
      Jason.encode!(%{
        "mcpServers" => %{
          "repo_authored_dot_mcp" => %{
            "type" => "stdio",
            "command" => "node",
            "args" => ["repo-authored-dot-mcp.js"]
          }
        }
      })
    )

    File.write!(
      Path.join(workspace, "mcp.json"),
      Jason.encode!(%{
        "mcpServers" => %{
          "repo_authored_root_mcp" => %{
            "type" => "stdio",
            "command" => "node",
            "args" => ["repo-authored-root-mcp.js"]
          }
        }
      })
    )

    codebuddy_dir = Path.join(workspace, ".codebuddy")
    File.mkdir_p!(codebuddy_dir)

    File.write!(
      Path.join(codebuddy_dir, "settings.json"),
      Jason.encode!(%{
        "enabledMcpjsonServers" => ["repo_authored_dot_mcp"],
        "enableAllProjectMcpServers" => true,
        "enabledPlugins" => ["repo-plugin"],
        "permissions" => %{"allow" => ["mcp__repo_authored_dot_mcp"]}
      })
    )

    File.mkdir_p!(Path.join([workspace, ".codebuddy", "plugins", "repo-plugin"]))

    File.write!(
      Path.join([workspace, ".codebuddy", "plugins", "repo-plugin", ".mcp.json"]),
      Jason.encode!(%{"mcpServers" => %{"repo_plugin" => %{}}})
    )

    File.mkdir_p!(Path.join([workspace, "plugins", "repo-plugin"]))

    File.write!(
      Path.join([workspace, "plugins", "repo-plugin", ".mcp.json"]),
      Jason.encode!(%{"mcpServers" => %{"repo_plugin" => %{}}})
    )
  end

  defp write_fake_acp_script!(workspace, mode) do
    path = Path.join(workspace, "fake_codebuddy_#{mode}.sh")
    File.write!(path, String.trim_leading(fake_acp_script(mode)))
    File.chmod!(path, 0o755)
    path
  end

  defp write_fake_acp_http_launcher_script!(workspace, port) do
    path = Path.join(workspace, "fake_codebuddy_http.sh")

    File.write!(
      path,
      """
      #!/usr/bin/env bash
      script_dir="$(cd "$(dirname "$0")" && pwd)"
      printf '%s\\n' "$@" > "$script_dir/codebuddy_http_args.txt"
      printf '%s\\n' "$CODEBUDDY_API_KEY" > "$script_dir/codebuddy_api_key.txt"
      printf '%s\\n' "$CODEBUDDY_AUTH_TOKEN" > "$script_dir/codebuddy_auth_token.txt"
      printf '%s\\n' "$CODEBUDDY_BASE_URL" > "$script_dir/codebuddy_base_url.txt"
      printf '%s\\n' "$CODEBUDDY_INTERNET_ENVIRONMENT" > "$script_dir/codebuddy_internet_environment.txt"
      printf 'Endpoint  http://127.0.0.1:#{port}\\n'
      while true; do sleep 1; done
      """
      |> String.trim_leading()
    )

    File.chmod!(path, 0o755)
    path
  end

  defp fake_acp_script(:success) do
    """
    #!/usr/bin/env bash
    while IFS= read -r line; do
      case "$line" in
        *initialize*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":0,"result":{"protocolVersion":1,"agentCapabilities":{"promptCapabilities":{"image":true,"embeddedContext":true},"mcpCapabilities":{"http":true,"sse":true},"loadSession":true,"delegateToolsSupport":true},"authMethods":[]}}'
          ;;
        *session/new*)
          printf '%s\\n' '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"codebuddy-session-1","update":{"sessionUpdate":"available_commands_update","availableCommands":[]}}}'
          printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"sessionId":"codebuddy-session-1","models":{"availableModels":[],"currentModelId":"glm-5.1"},"modes":{"availableModes":[{"id":"plan"}],"currentModeId":"plan"},"configOptions":[]}}'
          ;;
        *session/prompt*)
          printf '%s\\n' '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"codebuddy-session-1","update":{"sessionUpdate":"session_info_update","_meta":{"codebuddy.ai/agentPhase":{"phase":"model_streaming"}}}}}'
          printf '%s\\n' '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"codebuddy-session-1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"pong"},"messageId":"assistant-message-1"}}}'
          printf '%s\\n' '{"jsonrpc":"2.0","id":2,"result":{"stopReason":"end_turn","userMessageId":"codebuddy-user-message-1","_meta":{"codebuddy.ai/finishReason":"stop","codebuddy.ai/requestId":"secret-request-id"}}}'
          ;;
      esac
    done
    """
  end

  defp fake_acp_script(:available_model_success) do
    """
    #!/usr/bin/env bash
    while IFS= read -r line; do
      case "$line" in
        *initialize*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":0,"result":{"protocolVersion":1,"agentCapabilities":{"promptCapabilities":{"image":true,"embeddedContext":true},"mcpCapabilities":{"http":true,"sse":true},"loadSession":true,"delegateToolsSupport":true},"authMethods":[]}}'
          ;;
        *session/new*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"sessionId":"codebuddy-session-1","models":{"availableModels":[{"id":"glm-5.1"},{"modelId":"glm-5.1-pro"}],"currentModelId":"glm-5.1"},"modes":{"availableModes":[{"id":"plan"}],"currentModeId":"plan"},"configOptions":[]}}'
          ;;
        *session/prompt*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":2,"result":{"stopReason":"end_turn","userMessageId":"codebuddy-user-message-1","_meta":{"codebuddy.ai/finishReason":"stop"}}}'
          ;;
      esac
    done
    """
  end

  defp fake_acp_script(:success_with_child) do
    """
    #!/usr/bin/env bash
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    sleep 60 &
    printf '%s\\n' "$!" > "$script_dir/codebuddy_child.pid"

    while IFS= read -r line; do
      case "$line" in
        *initialize*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":0,"result":{"protocolVersion":1,"agentCapabilities":{"promptCapabilities":{"image":true,"embeddedContext":true},"mcpCapabilities":{"http":true,"sse":true},"loadSession":true,"delegateToolsSupport":true},"authMethods":[]}}'
          ;;
        *session/new*)
          printf '%s\\n' '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"codebuddy-session-1","update":{"sessionUpdate":"available_commands_update","availableCommands":[]}}}'
          printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"sessionId":"codebuddy-session-1","models":{"availableModels":[],"currentModelId":"glm-5.1"},"modes":{"availableModes":[{"id":"plan"}],"currentModeId":"plan"},"configOptions":[]}}'
          ;;
        *session/prompt*)
          printf '%s\\n' '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"codebuddy-session-1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"pong"},"messageId":"assistant-message-1"}}}'
          printf '%s\\n' '{"jsonrpc":"2.0","id":2,"result":{"stopReason":"end_turn","userMessageId":"codebuddy-user-message-1"}}'
          ;;
      esac
    done
    """
  end

  defp fake_acp_script(:success_exit_zero_after_prompt) do
    """
    #!/usr/bin/env bash
    while IFS= read -r line; do
      case "$line" in
        *initialize*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":0,"result":{"protocolVersion":1,"agentCapabilities":{"promptCapabilities":{"image":true,"embeddedContext":true},"mcpCapabilities":{"http":true,"sse":true},"loadSession":true,"delegateToolsSupport":true},"authMethods":[]}}'
          ;;
        *session/new*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"sessionId":"codebuddy-session-1","models":{"availableModels":[],"currentModelId":"glm-5.1"},"modes":{"availableModes":[{"id":"plan"}],"currentModeId":"plan"},"configOptions":[]}}'
          ;;
        *session/prompt*)
          printf '%s\\n' '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"codebuddy-session-1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"pong"},"messageId":"assistant-message-1"}}}'
          exit 0
          ;;
      esac
    done
    """
  end

  defp fake_acp_script(:record_argv_success) do
    """
    #!/usr/bin/env bash
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    printf '%s\\n' "$@" > "$script_dir/codebuddy_args.txt"
    printf '%s\\n' "$CODEBUDDY_API_KEY" > "$script_dir/codebuddy_api_key.txt"
    printf '%s\\n' "$CODEBUDDY_AUTH_TOKEN" > "$script_dir/codebuddy_auth_token.txt"
    printf '%s\\n' "$CODEBUDDY_BASE_URL" > "$script_dir/codebuddy_base_url.txt"
    printf '%s\\n' "$CODEBUDDY_INTERNET_ENVIRONMENT" > "$script_dir/codebuddy_internet_environment.txt"
    printf '%s\\n' "$SYMPHONY_DYNAMIC_TOOL_BRIDGE_BASE_URL" > "$script_dir/dynamic_tool_bridge_base_url.txt"
    printf '%s\\n' "$SYMPHONY_DYNAMIC_TOOL_BRIDGE_TRANSPORT" > "$script_dir/dynamic_tool_bridge_transport.txt"

    while IFS= read -r line; do
      case "$line" in
        *initialize*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":0,"result":{"protocolVersion":1,"agentCapabilities":{"promptCapabilities":{"image":true,"embeddedContext":true},"mcpCapabilities":{"http":true,"sse":true},"loadSession":true,"delegateToolsSupport":true},"authMethods":[]}}'
          ;;
        *session/new*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"sessionId":"codebuddy-session-1","models":{"availableModels":[],"currentModelId":"glm-5.1"},"modes":{"availableModes":[{"id":"plan"}],"currentModeId":"plan"},"configOptions":[]}}'
          ;;
        *session/prompt*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":2,"result":{"stopReason":"end_turn","userMessageId":"codebuddy-user-message-1","_meta":{"codebuddy.ai/finishReason":"stop"}}}'
          ;;
      esac
    done
    """
  end

  defp fake_acp_script(:permission_request) do
    """
    #!/usr/bin/env bash
    while IFS= read -r line; do
      case "$line" in
        *initialize*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":0,"result":{"protocolVersion":1,"agentCapabilities":{"promptCapabilities":{},"mcpCapabilities":{},"loadSession":true},"authMethods":[]}}'
          ;;
        *session/new*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"sessionId":"codebuddy-session-1","models":{"availableModels":[],"currentModelId":"glm-5.1"},"modes":{"availableModes":[{"id":"default"}],"currentModeId":"default"},"configOptions":[]}}'
          ;;
        *session/prompt*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":7,"method":"session/request_permission","params":{"toolCall":{"name":"Read","arguments":{"path":"package.json"}}}}'
          IFS= read -r _cancel_response || true
          ;;
      esac
    done
    """
  end

  defp fake_acp_script(:permission_request_then_success) do
    """
    #!/usr/bin/env bash
    script_dir="$(cd "$(dirname "$0")" && pwd)"

    while IFS= read -r line; do
      case "$line" in
        *initialize*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":0,"result":{"protocolVersion":1,"agentCapabilities":{"promptCapabilities":{},"mcpCapabilities":{},"loadSession":true},"authMethods":[]}}'
          ;;
        *session/new*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"sessionId":"codebuddy-session-1","models":{"availableModels":[],"currentModelId":"glm-5.1"},"modes":{"availableModes":[{"id":"default"}],"currentModeId":"default"},"configOptions":[]}}'
          ;;
        *session/prompt*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":7,"method":"session/request_permission","params":{"options":[{"kind":"allow_once","name":"Allow","optionId":"allow"},{"kind":"allow_always","name":"Always Allow","optionId":"allow_always"},{"kind":"reject_once","name":"Reject","optionId":"reject"}],"toolCall":{"name":"Bash","arguments":{"command":"git status"}}}}'
          IFS= read -r permission_response || true
          printf '%s\\n' "$permission_response" > "$script_dir/permission_response.json"
          printf '%s\\n' '{"jsonrpc":"2.0","id":2,"result":{"stopReason":"end_turn","_meta":{"codebuddy.ai/finishReason":"stop"}}}'
          ;;
      esac
    done
    """
  end

  defp dynamic_tool_context_for_test do
    %{
      source_context: %{},
      tool_specs: [
        %{
          "name" => "fake_dynamic_tool",
          "description" => "Fake dynamic tool.",
          "inputSchema" => %{"type" => "object"}
        }
      ],
      tool_metadata: %{},
      tool_environment: %{}
    }
  end

  defp empty_dynamic_tool_context_for_test do
    %{source_context: %{}, tool_specs: [], tool_metadata: %{}, tool_environment: %{}}
  end
end
