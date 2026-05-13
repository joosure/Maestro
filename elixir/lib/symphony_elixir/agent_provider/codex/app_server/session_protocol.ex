defmodule SymphonyElixir.AgentProvider.Codex.AppServer.SessionProtocol do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.AppServer.{EventFields, Protocol, StreamDiagnostics}
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @initialize_id 1
  @thread_start_id 2
  @turn_start_id 3

  @spec start_session(term(), Path.t(), map(), pos_integer()) :: {:ok, String.t()} | {:error, term()}
  def start_session(port, workspace, session_policies, read_timeout_ms)
      when is_binary(workspace) and is_map(session_policies) do
    case send_initialize(port, read_timeout_ms) do
      :ok -> start_thread(port, workspace, session_policies, read_timeout_ms)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec start_turn(term(), String.t(), String.t(), map(), Path.t(), String.t() | map(), map(), pos_integer()) ::
          {:ok, String.t()} | {:error, term()}
  def start_turn(
        port,
        thread_id,
        prompt,
        issue,
        workspace,
        approval_policy,
        turn_sandbox_policy,
        read_timeout_ms
      )
      when is_binary(thread_id) and is_binary(prompt) and is_map(turn_sandbox_policy) do
    Protocol.send_message(port, %{
      "method" => "turn/start",
      "id" => @turn_start_id,
      "params" => %{
        "threadId" => thread_id,
        "input" => [
          %{
            "type" => "text",
            "text" => prompt
          }
        ],
        "cwd" => workspace,
        "title" => "#{issue.identifier}: #{issue.title}",
        "approvalPolicy" => approval_policy,
        "sandboxPolicy" => turn_sandbox_policy
      }
    })

    case await_response(port, @turn_start_id, read_timeout_ms) do
      {:ok, %{"turn" => %{"id" => turn_id}}} -> {:ok, turn_id}
      other -> other
    end
  end

  defp send_initialize(port, read_timeout_ms) do
    payload = %{
      "method" => "initialize",
      "id" => @initialize_id,
      "params" => %{
        "capabilities" => %{
          "experimentalApi" => true
        },
        "clientInfo" => %{
          "name" => "symphony-orchestrator",
          "title" => "Symphony Orchestrator",
          "version" => "0.1.0"
        }
      }
    }

    Protocol.send_message(port, payload)

    with {:ok, _} <- await_response(port, @initialize_id, read_timeout_ms) do
      Protocol.send_message(port, %{"method" => "initialized", "params" => %{}})
      :ok
    end
  end

  defp start_thread(
         port,
         workspace,
         %{approval_policy: approval_policy, thread_sandbox: thread_sandbox},
         read_timeout_ms
       ) do
    Protocol.send_message(port, %{
      "method" => "thread/start",
      "id" => @thread_start_id,
      "params" => %{
        "approvalPolicy" => approval_policy,
        "sandbox" => thread_sandbox,
        "cwd" => workspace
      }
    })

    case await_response(port, @thread_start_id, read_timeout_ms) do
      {:ok, %{"thread" => thread_payload}} ->
        case thread_payload do
          %{"id" => thread_id} -> {:ok, thread_id}
          _ -> {:error, {:invalid_thread_payload, thread_payload}}
        end

      other ->
        other
    end
  end

  defp await_response(port, request_id, read_timeout_ms) do
    with_timeout_response(port, request_id, read_timeout_ms, "")
  end

  defp with_timeout_response(port, request_id, timeout_ms, pending_line) do
    receive do
      {^port, {:data, {:eol, chunk}}} ->
        complete_line = pending_line <> to_string(chunk)
        handle_response(port, request_id, complete_line, timeout_ms)

      {^port, {:data, {:noeol, chunk}}} ->
        with_timeout_response(port, request_id, timeout_ms, pending_line <> to_string(chunk))

      {^port, {:exit_status, status}} ->
        {:error, {:port_exit, status}}
    after
      timeout_ms ->
        {:error, :response_timeout}
    end
  end

  defp handle_response(port, request_id, data, timeout_ms) do
    payload = to_string(data)

    case Jason.decode(payload) do
      {:ok, %{"id" => ^request_id, "error" => error}} ->
        {:error, {:response_error, error}}

      {:ok, %{"id" => ^request_id, "result" => result}} ->
        {:ok, result}

      {:ok, %{"id" => ^request_id} = response_payload} ->
        {:error, {:response_error, response_payload}}

      {:ok, %{} = other} ->
        ObsLogger.text(
          :debug,
          "codex_response_ignored",
          %{
            event: :codex_response_ignored,
            component: "codex.app_server",
            payload_summary: EventFields.stream_summary(other)
          }
        )

        with_timeout_response(port, request_id, timeout_ms, "")

      {:error, _} ->
        StreamDiagnostics.log_response_line(payload, "response stream")
        with_timeout_response(port, request_id, timeout_ms, "")
    end
  end
end
