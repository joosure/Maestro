defmodule SymphonyElixir.Orchestrator.TerminalCleanup do
  @moduledoc false

  alias SymphonyElixir.Issue

  def run(opts \\ [])

  @spec run(keyword()) :: :ok
  def run(opts) when is_list(opts) do
    fetch_terminal_issues = Keyword.fetch!(opts, :fetch_terminal_issues)
    cleanup_workspace = Keyword.fetch!(opts, :cleanup_workspace)
    emit_event = Keyword.get(opts, :emit_event)

    case fetch_terminal_issues.() do
      {:ok, issues} ->
        identifiers =
          Enum.flat_map(issues, fn
            %Issue{identifier: identifier} when is_binary(identifier) -> [identifier]
            _ -> []
          end)

        case identifiers do
          [] ->
            skip_reason = if issues == [], do: "no_terminal_issues", else: "no_cleanup_targets"

            emit_event(emit_event, :info, :terminal_cleanup_skipped, %{
              skip_reason: skip_reason,
              result_summary: skip_reason,
              message: "terminal_cleanup_skipped reason=#{skip_reason}"
            })

          cleanup_targets ->
            Enum.each(cleanup_targets, &cleanup_workspace(cleanup_workspace, &1))

            emit_event(emit_event, :info, :terminal_cleanup_completed, %{
              result_summary: "cleanup_targets=#{length(cleanup_targets)}",
              message: "terminal_cleanup_completed cleanup_targets=#{length(cleanup_targets)}"
            })
        end

      {:error, reason} ->
        emit_event(emit_event, :warning, :terminal_cleanup_skipped, %{
          skip_reason: "fetch_failed",
          error: inspect(reason),
          result_summary: "fetch_failed",
          message: "terminal_cleanup_skipped reason=fetch_failed error=#{inspect(reason)}"
        })

        emit_event(emit_event, :warning, :startup_terminal_cleanup_failed, %{
          error: inspect(reason)
        })
    end

    :ok
  end

  defp cleanup_workspace(cleanup_workspace, identifier)
       when is_function(cleanup_workspace, 1) and is_binary(identifier) do
    cleanup_workspace.(identifier)
  end

  defp cleanup_workspace(_cleanup_workspace, _identifier), do: :ok

  defp emit_event(emit_event, level, event, extra_fields)
       when is_function(emit_event, 3) and is_map(extra_fields) do
    emit_event.(level, event, extra_fields)
  end

  defp emit_event(_emit_event, _level, _event, _extra_fields), do: :ok
end
