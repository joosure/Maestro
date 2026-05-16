defmodule SymphonyElixir.Orchestrator.TerminalCleanup do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger

  def run(opts \\ [])

  @spec run(keyword()) :: :ok
  def run(opts) when is_list(opts) do
    fetch_terminal_issues = Keyword.fetch!(opts, :fetch_terminal_issues)
    cleanup_workspace = Keyword.fetch!(opts, :cleanup_workspace)
    emit_event = Keyword.get(opts, :emit_event)

    case fetch_terminal_issues(fetch_terminal_issues) do
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
            cleanup_failures =
              cleanup_targets
              |> Enum.flat_map(fn identifier ->
                case cleanup_workspace(cleanup_workspace, identifier) do
                  :ok -> []
                  {:error, reason} -> [%{issue_identifier: identifier, reason: inspect(reason)}]
                end
              end)

            if cleanup_failures == [] do
              emit_event(emit_event, :info, :terminal_cleanup_completed, %{
                result_summary: "cleanup_targets=#{length(cleanup_targets)}",
                message: "terminal_cleanup_completed cleanup_targets=#{length(cleanup_targets)}"
              })
            else
              emit_event(emit_event, :warning, :startup_terminal_cleanup_failed, %{
                cleanup_targets: length(cleanup_targets),
                failed_cleanup_targets: length(cleanup_failures),
                cleanup_failures: cleanup_failures,
                error: inspect(cleanup_failures)
              })
            end
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

  defp fetch_terminal_issues(fetch_terminal_issues) when is_function(fetch_terminal_issues, 0) do
    case fetch_terminal_issues.() do
      {:ok, issues} when is_list(issues) -> {:ok, issues}
      {:ok, issues} -> {:error, {:invalid_terminal_cleanup_fetch_result, issues}}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_terminal_cleanup_fetch_result, other}}
    end
  rescue
    error ->
      {:error, ObservabilityLogger.format_error(error, __STACKTRACE__)}
  catch
    kind, reason ->
      {:error, ObservabilityLogger.format_error({kind, reason}, __STACKTRACE__)}
  end

  defp cleanup_workspace(cleanup_workspace, identifier)
       when is_function(cleanup_workspace, 1) and is_binary(identifier) do
    case cleanup_workspace.(identifier) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_terminal_cleanup_result, other}}
    end
  rescue
    error ->
      {:error, ObservabilityLogger.format_error(error, __STACKTRACE__)}
  catch
    kind, reason ->
      {:error, ObservabilityLogger.format_error({kind, reason}, __STACKTRACE__)}
  end

  defp cleanup_workspace(_cleanup_workspace, _identifier), do: :ok

  defp emit_event(emit_event, level, event, extra_fields)
       when is_function(emit_event, 3) and is_map(extra_fields) do
    emit_event.(level, event, extra_fields)
  end

  defp emit_event(_emit_event, _level, _event, _extra_fields), do: :ok
end
