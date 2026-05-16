defmodule SymphonyElixir.Agent.Runner.Prompts do
  @moduledoc false

  alias SymphonyElixir.Agent.Runner.ProviderOptions
  alias SymphonyElixir.{AgentProvider, Config}
  alias SymphonyElixir.Workflow.Prompt.Builder, as: PromptBuilder

  @spec build(term(), term(), keyword(), pos_integer(), pos_integer()) :: String.t()
  def build(session, issue, opts, 1, _max_turns) do
    rendered_workflow_prompt(session, issue, opts)
  end

  def build(session, issue, opts, turn_number, max_turns) do
    if stateful_provider?(session) do
      continuation_prompt(turn_number, max_turns, true)
    else
      continuation = continuation_prompt(turn_number, max_turns, false)

      """
      #{continuation}

      Stateless provider context:

      - This provider does not declare reusable session context, so the rendered workflow prompt is included again.
      - Treat the prompt below as the governing task policy for the current workspace state.

      Rendered workflow prompt:

      #{rendered_workflow_prompt(session, issue, opts)}
      """
    end
  end

  defp stateful_provider?(session) do
    AgentProvider.supports?("agent.session.stateful", ProviderOptions.from_session(session))
  end

  defp continuation_prompt(turn_number, max_turns, true) do
    """
    Continuation guidance:

    - The previous agent turn completed normally, but the issue is still in an active state.
    - This is continuation turn ##{turn_number} of #{max_turns} for the current agent run.
    - Resume from the current workspace and workpad state instead of restarting from scratch.
    - The original task instructions and prior turn context are already present in this thread, so do not restate them before acting.
    - Focus on the remaining ticket work and do not end the turn while the issue stays active unless you are truly blocked.
    """
  end

  defp continuation_prompt(turn_number, max_turns, false) do
    """
    Continuation guidance:

    - The previous agent turn completed normally, but the issue is still in an active state.
    - This is continuation turn ##{turn_number} of #{max_turns} for the current agent run.
    - Resume from the current workspace and workpad state instead of restarting from scratch.
    - Use the rendered workflow prompt below as the task and policy context for this stateless turn.
    - Focus on the remaining ticket work and do not end the turn while the issue stays active unless you are truly blocked.
    """
  end

  defp rendered_workflow_prompt(session, issue, opts) do
    settings = Config.settings!()

    opts
    |> put_session_tool_context(session)
    |> put_session_provider_kind(session)
    |> Keyword.put_new(:settings, settings)
    |> Keyword.put_new(:repo, settings.repo)
    |> then(&PromptBuilder.build_prompt(issue, &1))
  end

  defp put_session_tool_context(opts, session) when is_list(opts) do
    case session_tool_context(session) do
      tool_context when is_map(tool_context) -> Keyword.put_new(opts, :tool_context, tool_context)
      _tool_context -> opts
    end
  end

  defp session_tool_context(%{provider_state: provider_state}), do: session_tool_context(provider_state)
  defp session_tool_context(%{tool_context: tool_context}), do: tool_context
  defp session_tool_context(%{"tool_context" => tool_context}), do: tool_context
  defp session_tool_context(_session), do: nil

  defp put_session_provider_kind(opts, session) when is_list(opts) do
    case session_provider_kind(session) do
      kind when is_binary(kind) -> Keyword.put_new(opts, :agent_provider_kind, kind)
      _kind -> opts
    end
  end

  defp session_provider_kind(%{agent_provider_kind: kind}) when is_binary(kind), do: kind
  defp session_provider_kind(%{"agent_provider_kind" => kind}) when is_binary(kind), do: kind
  defp session_provider_kind(%{provider_kind: kind}) when is_binary(kind), do: kind
  defp session_provider_kind(%{"provider_kind" => kind}) when is_binary(kind), do: kind
  defp session_provider_kind(%{provider_state: provider_state}), do: session_provider_kind(provider_state)
  defp session_provider_kind(_session), do: nil
end
