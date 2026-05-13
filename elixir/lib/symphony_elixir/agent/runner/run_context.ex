defmodule SymphonyElixir.Agent.Runner.RunContext do
  @moduledoc false

  alias SymphonyElixir.Issue

  @type worker_host :: String.t() | nil

  @spec selected_worker_host(String.t() | nil, [String.t()]) :: worker_host()
  def selected_worker_host(nil, []), do: nil

  def selected_worker_host(preferred_host, configured_hosts) when is_list(configured_hosts) do
    hosts =
      configured_hosts
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    case preferred_host do
      host when is_binary(host) and host != "" -> host
      _ when hosts == [] -> nil
      _ -> List.first(hosts)
    end
  end

  @spec run_issue_context(term(), String.t()) :: term()
  def run_issue_context(%Issue{id: issue_id, identifier: identifier}, run_id) do
    %{
      id: issue_id,
      identifier: identifier,
      run_id: run_id
    }
  end

  def run_issue_context(issue, _run_id), do: issue

  @spec issue_context(Issue.t()) :: String.t()
  def issue_context(%Issue{id: issue_id, identifier: identifier}) do
    "issue_id=#{issue_id} issue_identifier=#{identifier}"
  end

  @spec failure_class_field(nil | String.t()) :: map()
  def failure_class_field(nil), do: %{}
  def failure_class_field(failure_class), do: %{failure_class: failure_class}

  @spec remote_startup_result({:error, term()}, worker_host()) :: {:error, term()}
  def remote_startup_result({:error, reason}, worker_host) when is_binary(worker_host),
    do: {:error, {:remote_startup_failure, reason}}

  def remote_startup_result({:error, _reason} = error, _worker_host), do: error

  @spec workspace_result({:error, term()}, worker_host()) :: {:error, term()}
  def workspace_result({:error, reason}, worker_host) when is_binary(worker_host),
    do: {:error, {:in_workspace_agent_failure, reason}}

  def workspace_result({:error, _reason} = error, _worker_host), do: error

  @spec monotonic_ms() :: integer()
  def monotonic_ms, do: System.monotonic_time(:millisecond)

  @spec elapsed_ms(integer()) :: non_neg_integer()
  def elapsed_ms(started_at_ms), do: max(monotonic_ms() - started_at_ms, 0)

  @spec generate_run_id(term()) :: String.t()
  def generate_run_id(%Issue{id: issue_id}) when is_binary(issue_id) do
    "run-" <> Integer.to_string(System.unique_integer([:positive])) <> "-" <> issue_id
  end

  def generate_run_id(_issue) do
    "run-" <> Integer.to_string(System.unique_integer([:positive]))
  end
end
