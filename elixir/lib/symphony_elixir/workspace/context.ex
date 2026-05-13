defmodule SymphonyElixir.Workspace.Context do
  @moduledoc false

  alias SymphonyElixir.Tracker

  @type worker_host :: String.t() | nil
  @type issue_context :: %{
          issue_id: term(),
          issue_identifier: String.t(),
          run_id: String.t() | nil
        }

  @spec issue_context(map() | String.t() | nil) :: issue_context()
  def issue_context(%{id: issue_id, identifier: identifier, run_id: run_id}) do
    %{
      issue_id: issue_id,
      issue_identifier: identifier || "issue",
      run_id: run_id
    }
  end

  def issue_context(%{id: issue_id, identifier: identifier}) do
    %{
      issue_id: issue_id,
      issue_identifier: identifier || "issue",
      run_id: nil
    }
  end

  def issue_context(identifier) when is_binary(identifier) do
    %{
      issue_id: nil,
      issue_identifier: identifier,
      run_id: nil
    }
  end

  def issue_context(_identifier) do
    %{
      issue_id: nil,
      issue_identifier: "issue",
      run_id: nil
    }
  end

  @spec workspace_context(Path.t()) :: issue_context()
  def workspace_context(workspace) when is_binary(workspace) do
    issue_context(Path.basename(workspace))
  end

  @spec event_fields(issue_context(), Path.t() | nil, worker_host(), map()) :: map()
  def event_fields(issue_context, workspace, worker_host, extra \\ %{})
      when is_map(issue_context) and is_map(extra) do
    %{
      component: "workspace",
      tracker_kind: tracker_kind(),
      run_id: issue_context[:run_id],
      correlation_id: issue_context[:run_id],
      issue_id: issue_context[:issue_id],
      issue_identifier: issue_context[:issue_identifier],
      workspace_path: workspace,
      worker_host: worker_host
    }
    |> Map.merge(extra)
  end

  defp tracker_kind, do: Tracker.current_kind()
end
