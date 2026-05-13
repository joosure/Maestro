defmodule SymphonyElixir.AgentProvider.Mock.Adapter do
  @moduledoc """
  Local no-op agent provider for development, demos, and workflow-template smoke
  tests.

  The adapter satisfies the provider contract without starting an external
  process, reading credentials, or contacting a network service.
  """

  @behaviour SymphonyElixir.AgentProvider.Adapter

  alias SymphonyElixir.AgentProvider.{Config, EventSummary, Session, TurnResult}

  @provider_kind "mock"
  @supported_options ~w(message turn_status session_id thread_id turn_id complete_issue_state)
  @supported_statuses ~w(completed failed cancelled input_required timeout)
  @default_message "Mock agent completed a local Symphony turn without external credentials."

  @impl true
  def kind, do: @provider_kind

  @impl true
  def defaults do
    %{
      "message" => @default_message,
      "turn_status" => "completed"
    }
  end

  @impl true
  def capabilities, do: ["agent.turn.run"]

  @impl true
  def validate_options(options) when is_map(options) do
    with :ok <- validate_supported_options(options),
         :ok <- validate_string_option(options, "message"),
         :ok <- validate_string_option(options, "session_id"),
         :ok <- validate_string_option(options, "thread_id"),
         :ok <- validate_string_option(options, "turn_id"),
         :ok <- validate_string_option(options, "complete_issue_state"),
         :ok <- validate_turn_status(Map.get(options, "turn_status")) do
      :ok
    end
  end

  def validate_options(_options), do: {:error, :invalid_mock_agent_provider_options}

  @impl true
  def finalize_options(options) when is_map(options) do
    options
    |> Map.put("message", normalize_message(Map.get(options, "message")))
    |> Map.put("turn_status", normalize_turn_status(Map.get(options, "turn_status")))
  end

  @impl true
  def validate_config(%Config{options: options}), do: validate_options(options)
  def validate_config(_config), do: {:error, :invalid_mock_agent_provider_config}

  @impl true
  def prepare_workspace(%Config{}, _workspace, _opts \\ []), do: :ok

  @impl true
  def start_session(%Config{} = config, workspace, opts \\ []) do
    session_id = configured_or_generated_id(config, "session_id", "mock-session")
    thread_id = configured_or_generated_id(config, "thread_id", "mock-thread")

    {:ok,
     Session.new(
       agent_provider_kind: @provider_kind,
       provider_state: %{
         message: Map.get(config.options, "message", @default_message),
         turn_status: Map.get(config.options, "turn_status", "completed")
       },
       run_id: Keyword.get(opts, :run_id),
       session_id: session_id,
       thread_id: thread_id,
       workspace: workspace,
       worker_host: Keyword.get(opts, :worker_host),
       metadata: %{local_only: true}
     )}
  end

  @impl true
  def run_turn(%Config{} = config, %Session{} = session, prompt, issue, opts \\ []) do
    status = Map.get(config.options, "turn_status", "completed") |> status_atom()
    message = Map.get(config.options, "message", @default_message)
    turn_id = configured_or_generated_id(config, "turn_id", "mock-turn")

    with :ok <- maybe_complete_issue(config, issue) do
      notify_message(opts, session, issue, prompt, status, message, turn_id)

      {:ok,
       TurnResult.new(
         status: status,
         session_id: session.session_id,
         thread_id: session.thread_id,
         turn_id: turn_id,
         usage: %{
           "input_tokens" => 0,
           "output_tokens" => 0,
           "total_tokens" => 0
         },
         local_only: true
       )}
    end
  end

  @impl true
  def stop_session(%Config{}, %Session{}, _opts \\ []), do: :ok

  @impl true
  def session_stop_options(%Config{}, _result, _issue), do: []

  @impl true
  def failed_session_stop_options(%Config{}, _issue, _error), do: []

  @impl true
  def summarize_message(%{message: nested}), do: summarize_message(nested)
  def summarize_message(%{"message" => nested}), do: summarize_message(nested)

  def summarize_message(%{payload: %{summary: summary}}) when is_binary(summary),
    do: EventSummary.new(summary, provider_kind: @provider_kind, event: :mock_turn_completed, category: :turn)

  def summarize_message(%{"payload" => %{"summary" => summary}}) when is_binary(summary),
    do: EventSummary.new(summary, provider_kind: @provider_kind, event: :mock_turn_completed, category: :turn)

  def summarize_message(message), do: EventSummary.from_term(message, provider_kind: @provider_kind)

  @impl true
  def session_log_event?(_component, _event), do: false

  @impl true
  def workspace_automation_destination_dir, do: ".mock-agent"

  defp validate_supported_options(options) do
    unsupported =
      options
      |> Map.keys()
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 in @supported_options))
      |> Enum.sort()

    case unsupported do
      [] -> :ok
      keys -> {:error, {:unsupported_agent_provider_options, @provider_kind, keys}}
    end
  end

  defp validate_string_option(options, key) do
    case Map.get(options, key) do
      nil -> :ok
      value when is_binary(value) -> :ok
      value -> {:error, {:invalid_mock_agent_provider_option, key, value}}
    end
  end

  defp validate_turn_status(nil), do: :ok
  defp validate_turn_status(status) when status in @supported_statuses, do: :ok

  defp validate_turn_status(status),
    do: {:error, {:invalid_mock_turn_status, status, @supported_statuses}}

  defp normalize_message(message) when is_binary(message) do
    case String.trim(message) do
      "" -> @default_message
      trimmed -> trimmed
    end
  end

  defp normalize_message(_message), do: @default_message

  defp normalize_turn_status(status) when status in @supported_statuses, do: status
  defp normalize_turn_status(_status), do: "completed"

  defp status_atom("failed"), do: :failed
  defp status_atom("cancelled"), do: :cancelled
  defp status_atom("input_required"), do: :input_required
  defp status_atom("timeout"), do: :timeout
  defp status_atom(_status), do: :completed

  defp configured_or_generated_id(%Config{options: options}, key, prefix) do
    case Map.get(options, key) do
      value when is_binary(value) and value != "" -> value
      _value -> prefix <> "-" <> Integer.to_string(System.unique_integer([:positive]))
    end
  end

  defp maybe_complete_issue(%Config{options: options}, issue) do
    case {Map.get(options, "complete_issue_state"), issue_id(issue)} do
      {state_name, issue_id} when is_binary(state_name) and state_name != "" and is_binary(issue_id) ->
        SymphonyElixir.Tracker.update_issue_state(issue_id, state_name)

      _other ->
        :ok
    end
  end

  defp notify_message(opts, session, issue, prompt, status, message, turn_id) do
    case Keyword.get(opts, :on_message) do
      on_message when is_function(on_message, 1) ->
        on_message.(%{
          agent_provider_kind: @provider_kind,
          event: :mock_turn_completed,
          timestamp: DateTime.utc_now(),
          run_id: session.run_id,
          session_id: session.session_id,
          thread_id: session.thread_id,
          turn_id: turn_id,
          payload: %{
            summary: message,
            status: Atom.to_string(status),
            issue_identifier: issue_identifier(issue),
            prompt_bytes: byte_size(to_string(prompt))
          }
        })

      _on_message ->
        :ok
    end
  end

  defp issue_id(%{id: id}) when is_binary(id), do: id
  defp issue_id(%{"id" => id}) when is_binary(id), do: id
  defp issue_id(_issue), do: nil

  defp issue_identifier(%{identifier: identifier}) when is_binary(identifier), do: identifier
  defp issue_identifier(%{"identifier" => identifier}) when is_binary(identifier), do: identifier
  defp issue_identifier(_issue), do: nil
end
