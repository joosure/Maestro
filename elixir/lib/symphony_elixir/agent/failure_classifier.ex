defmodule SymphonyElixir.Agent.FailureClassifier do
  @moduledoc false

  @spec classify_worker_failure(term(), String.t() | nil) :: String.t() | nil
  def classify_worker_failure(_reason, nil), do: nil

  def classify_worker_failure({:remote_startup_failure, :ssh_not_found}, _worker_host),
    do: "host_connect_failure"

  def classify_worker_failure({:remote_startup_failure, reason}, _worker_host)
      when reason in [:ssh_not_found, :bash_not_found],
      do: "host_connect_failure"

  def classify_worker_failure(
        {:remote_startup_failure, {:invalid_workspace_cwd, _reason, _path}},
        _worker_host
      ),
      do: "workspace_validation_failure"

  def classify_worker_failure(
        {:remote_startup_failure, {:invalid_workspace_cwd, _reason, _arg1, _arg2}},
        _worker_host
      ),
      do: "workspace_validation_failure"

  def classify_worker_failure({:remote_startup_failure, _reason}, _worker_host),
    do: "remote_startup_failure"

  def classify_worker_failure({:in_workspace_agent_failure, _reason}, _worker_host),
    do: "in_workspace_agent_failure"

  def classify_worker_failure({:workspace_outside_root, _workspace, _root}, _worker_host),
    do: "workspace_validation_failure"

  def classify_worker_failure({:workspace_equals_root, _workspace, _root}, _worker_host),
    do: "workspace_validation_failure"

  def classify_worker_failure({:workspace_path_unreadable, _workspace, _reason}, _worker_host),
    do: "workspace_validation_failure"

  def classify_worker_failure({:workspace_hook_timeout, hook_name, _timeout_ms}, _worker_host)
      when hook_name in ["after_create", "before_run", "remote_command"],
      do: "workspace_prepare_failure"

  def classify_worker_failure({:workspace_hook_failed, hook_name, _status, _output}, _worker_host)
      when hook_name in ["after_create", "before_run"],
      do: "workspace_prepare_failure"

  def classify_worker_failure(
        {:workspace_bootstrap_automation_copy_failed, _host, _reason},
        _worker_host
      ),
      do: "workspace_prepare_failure"

  def classify_worker_failure(
        {:workspace_bootstrap_automation_copy_failed, _host, _status, _output},
        _worker_host
      ),
      do: "workspace_prepare_failure"

  def classify_worker_failure({:workspace_prepare_failed, _host, _status, _output}, _worker_host),
    do: "workspace_prepare_failure"

  def classify_worker_failure({:issue_state_refresh_failed, _reason}, _worker_host), do: nil
  def classify_worker_failure(_reason, _worker_host), do: nil
end
