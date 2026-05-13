defmodule SymphonyElixir.AgentProvider.AppServer.EventFields do
  @moduledoc false

  alias SymphonyElixir.Observability.Redaction

  @spec build(map(), Path.t() | nil, String.t() | nil, map() | nil, map(), keyword()) :: map()
  def build(base_fields, workspace, worker_host, issue, extra, opts \\ [])
      when is_map(base_fields) and is_map(extra) and is_list(opts) do
    base_fields
    |> Map.put(:workspace_path, workspace)
    |> Map.put(:worker_host, worker_host)
    |> Map.merge(issue_fields(issue, opts))
    |> Map.merge(extra)
  end

  @spec turn(map(), map() | nil, map()) :: map()
  def turn(base_fields, nil, extra), do: build(base_fields, nil, nil, nil, extra)

  def turn(base_fields, turn_context, extra)
      when is_map(base_fields) and is_map(turn_context) and is_map(extra) do
    build(
      base_fields,
      Map.get(turn_context, :workspace),
      Map.get(turn_context, :worker_host),
      Map.get(turn_context, :issue),
      Map.merge(
        %{
          run_id: Map.get(turn_context, :run_id),
          correlation_id: Map.get(turn_context, :run_id),
          session_id: Map.get(turn_context, :session_id),
          thread_id: Map.get(turn_context, :thread_id),
          turn_id: Map.get(turn_context, :turn_id)
        },
        extra
      )
    )
  end

  @spec prompt_hash(String.t() | term()) :: non_neg_integer() | nil
  def prompt_hash(prompt) when is_binary(prompt), do: :erlang.phash2(prompt)
  def prompt_hash(_prompt), do: nil

  @spec stream_summary(term()) :: String.t()
  def stream_summary(payload), do: Redaction.summarize(payload, 256)

  defp issue_fields(%{} = issue, opts) do
    fields = %{
      issue_id: Map.get(issue, :id),
      issue_identifier: Map.get(issue, :identifier)
    }

    if Keyword.get(opts, :compact_issue_fields?, true), do: compact(fields), else: fields
  end

  defp issue_fields(_issue, opts) do
    if Keyword.get(opts, :compact_issue_fields?, true) do
      %{}
    else
      %{issue_id: nil, issue_identifier: nil}
    end
  end

  defp compact(fields) when is_map(fields) do
    fields
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
