defmodule SymphonyElixir.TestSupport do
  @workflow_prompt "You are an agent for this repository."

  alias SymphonyElixir.ChangeProposalReconciliation.{CandidateInbox, KnownTarget}
  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Workflow.Runtime.Store, as: WorkflowStore
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Store, as: ReadinessStore

  defmacro __using__(_opts) do
    quote do
      use ExUnit.Case
      import ExUnit.CaptureLog

      alias SymphonyElixir.Agent.Runner, as: AgentRunner
      alias SymphonyElixir.AgentProvider.Codex.AppServer
      alias SymphonyElixir.CLI
      alias SymphonyElixir.Config
      alias SymphonyElixir.HttpServer
      alias SymphonyElixir.Issue
      alias SymphonyElixir.Observability.StatusDashboard
      alias SymphonyElixir.Orchestrator
      alias SymphonyElixir.Tracker
      alias SymphonyElixir.Tracker.Linear.Client
      alias SymphonyElixir.Workflow
      alias SymphonyElixir.Workflow.Prompt.Builder, as: PromptBuilder
      alias SymphonyElixir.Workflow.Runtime.Store, as: WorkflowStore
      alias SymphonyElixir.Workspace

      import SymphonyElixir.TestSupport,
        only: [
          ensure_supervisor_running: 0,
          restart_supervised_child: 1,
          terminate_supervised_child: 1,
          write_workflow_file!: 1,
          write_workflow_file!: 2,
          codex_app_server_opts: 1,
          codex_app_server_opts: 2,
          codex_provider_runtime_context: 1,
          codex_provider_runtime_context: 2,
          restore_env: 2,
          stop_default_http_server: 0
        ]

      setup do
        workflow_root =
          Path.join(
            System.tmp_dir!(),
            "symphony-elixir-workflow-#{System.unique_integer([:positive])}"
          )

        File.mkdir_p!(workflow_root)
        workflow_file = Path.join(workflow_root, "WORKFLOW.md")
        write_workflow_file!(workflow_file)
        Workflow.set_workflow_file_path(workflow_file)
        ensure_supervisor_running()

        if Process.whereis(WorkflowStore), do: WorkflowStore.force_reload()

        if Process.whereis(EventStore), do: EventStore.reset()
        if Process.whereis(CandidateInbox), do: CandidateInbox.reset()
        if Process.whereis(KnownTarget.Registry), do: KnownTarget.Registry.reset()
        if Process.whereis(ReadinessStore), do: ReadinessStore.reset()

        stop_default_http_server()

        on_exit(fn ->
          Application.delete_env(:symphony_elixir, :workflow_file_path)
          Application.delete_env(:symphony_elixir, :server_port_override)
          Application.delete_env(:symphony_elixir, :memory_tracker_issues)
          Application.delete_env(:symphony_elixir, :memory_tracker_recipient)
          File.rm_rf(workflow_root)
        end)

        :ok
      end
    end
  end

  def write_workflow_file!(path, overrides \\ []) do
    workflow = workflow_content(overrides)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, workflow)

    if Process.whereis(WorkflowStore) do
      try do
        WorkflowStore.force_reload()
      catch
        :exit, _reason -> :ok
      end
    end

    :ok
  end

  def restore_env(key, nil), do: System.delete_env(key)
  def restore_env(key, value), do: System.put_env(key, value)

  def codex_app_server_opts(workspace, opts \\ []) when is_binary(workspace) and is_list(opts) do
    opts
    |> Keyword.put_new(:codex_settings, SymphonyElixir.AgentProvider.Codex.Settings.current!())
    |> Keyword.put_new(:provider_runtime_context, codex_provider_runtime_context(workspace, opts))
  end

  def codex_provider_runtime_context(workspace, opts \\ []) when is_binary(workspace) and is_list(opts) do
    settings = SymphonyElixir.Config.settings!()

    {:ok, turn_sandbox_policy} =
      SymphonyElixir.Config.Schema.resolve_runtime_turn_sandbox_policy(
        settings,
        workspace,
        remote: is_binary(Keyword.get(opts, :worker_host)) or Keyword.get(opts, :remote, false)
      )

    %{
      workspace_root: settings.workspace.root,
      hook_timeout_ms: settings.hooks.timeout_ms,
      turn_sandbox_policy: turn_sandbox_policy
    }
  end

  def restart_supervised_child(child_id) do
    with_supervisor_retry(fn ->
      case Supervisor.restart_child(SymphonyElixir.Supervisor, child_id) do
        {:ok, _pid} -> :ok
        {:ok, _pid, _info} -> :ok
        {:error, :running} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        other -> other
      end
    end)
  end

  def terminate_supervised_child(child_id) do
    with_supervisor_retry(fn ->
      case Supervisor.terminate_child(SymphonyElixir.Supervisor, child_id) do
        :ok -> :ok
        {:error, :not_found} -> :ok
        other -> other
      end
    end)
  end

  def ensure_supervisor_running do
    case wait_for_supervisor(5) do
      :ok ->
        :ok

      :error ->
        raise "SymphonyElixir.Supervisor is unavailable after startup attempts"
    end
  end

  defp wait_for_supervisor(0), do: :error

  defp wait_for_supervisor(attempts_left) when is_integer(attempts_left) and attempts_left > 0 do
    case supervisor_children() do
      {:ok, _children} ->
        :ok

      :error ->
        case Application.ensure_all_started(:symphony_elixir) do
          {:ok, _apps} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

        Process.sleep(10)
        wait_for_supervisor(attempts_left - 1)
    end
  end

  def stop_default_http_server do
    case supervisor_children() do
      {:ok, children} ->
        case Enum.find(children, fn
               {SymphonyElixir.HttpServer, _child_pid, _type, _modules} -> true
               _child -> false
             end) do
          {SymphonyElixir.HttpServer, http_server_pid, _type, _modules} when is_pid(http_server_pid) ->
            try do
              case Supervisor.terminate_child(SymphonyElixir.Supervisor, SymphonyElixir.HttpServer) do
                :ok -> :ok
                {:error, :not_found} -> :ok
              end
            catch
              :exit, _reason -> :ok
            end

            if Process.alive?(http_server_pid) do
              Process.exit(http_server_pid, :normal)
            end

            :ok

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end

  defp supervisor_children do
    case Process.whereis(SymphonyElixir.Supervisor) do
      pid when is_pid(pid) ->
        try do
          {:ok, Supervisor.which_children(SymphonyElixir.Supervisor)}
        catch
          :exit, _reason -> :error
        end

      _ ->
        :error
    end
  end

  defp with_supervisor_retry(fun, attempts_left \\ 5)

  defp with_supervisor_retry(fun, attempts_left)
       when is_function(fun, 0) and is_integer(attempts_left) and attempts_left > 0 do
    ensure_supervisor_running()

    try do
      case fun.() do
        {:error, :restarting} when attempts_left > 1 ->
          Process.sleep(25)
          with_supervisor_retry(fun, attempts_left - 1)

        other ->
          other
      end
    catch
      :exit, reason ->
        if attempts_left > 1 do
          Process.sleep(25)
          with_supervisor_retry(fun, attempts_left - 1)
        else
          :erlang.raise(:exit, reason, __STACKTRACE__)
        end
    end
  end

  defp workflow_content(overrides) do
    config =
      Keyword.merge(
        [
          tracker_kind: "linear",
          tracker_endpoint: "https://api.linear.app/graphql",
          tracker_auth: nil,
          tracker_provider: nil,
          tracker_lifecycle: nil,
          tracker_api_token: "token",
          tracker_api_secret: nil,
          tracker_project_slug: "project",
          tracker_assignee: nil,
          tracker_active_states: ["Todo", "In Progress"],
          tracker_terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"],
          tracker_state_phase_map: :default,
          tracker_raw_state_by_route_key: nil,
          tracker_policy_by_route_key: nil,
          tracker_workflows_by_type: nil,
          tracker_platform: %{},
          workflow_profile: nil,
          workflow_profile_kind: nil,
          workflow_profile_version: nil,
          workflow_profile_options: nil,
          workflow_reconciliation: nil,
          poll_interval_ms: 30_000,
          workspace_root: Path.join(System.tmp_dir!(), "symphony_workspaces"),
          workspace_bootstrap_automation_from: nil,
          worker_ssh_hosts: [],
          worker_max_concurrent_local_agents: nil,
          worker_max_concurrent_agents_per_host: nil,
          agent_runtime: nil,
          repo_path: nil,
          repo_base_branch: "main",
          repo_remote_name: nil,
          repo_remote_url: nil,
          repo_branch_work_prefix: nil,
          repo_provider_kind: "github",
          repo_provider_repository: nil,
          repo_provider_api_base_url: nil,
          repo_provider_web_base_url: nil,
          repo_provider_required_pr_label: nil,
          max_concurrent_agents: 10,
          max_turns: 20,
          max_retry_backoff_ms: 300_000,
          max_concurrent_agents_by_state: %{},
          agent_credentials_enabled: false,
          agent_credentials_store_root: Path.join(System.tmp_dir!(), "symphony_agent_credentials"),
          agent_credentials_allow_host_auth_reuse: false,
          agent_credentials_rotation_strategy: "usage_aware_round_robin",
          agent_credentials_max_concurrent_leases_per_account: 1,
          agent_credentials_lease_timeout_ms: 10_000,
          agent_credentials_default_ttl_ms: 3_600_000,
          agent_credentials_exhausted_cooldown_ms: 300_000,
          agent_credentials_daily_token_budget: nil,
          agent_quota_preflight: "off",
          agent_quota_poller_enabled: false,
          agent_quota_poll_interval_ms: 300_000,
          agent_quota_probe_timeout_ms: 15_000,
          agent_quota_poll_providers: [],
          agent_provider_kind: "codex",
          agent_provider_options: %{},
          hook_after_create: nil,
          hook_before_run: nil,
          hook_after_run: nil,
          hook_before_remove: nil,
          hook_timeout_ms: 60_000,
          observability_enabled: true,
          observability_refresh_ms: 1_000,
          observability_render_interval_ms: 16,
          observability_file_enabled: true,
          observability_console_enabled: false,
          observability_log_format: "json",
          observability_summary_max_bytes: 512,
          observability_global_event_limit: 1_000,
          observability_issue_event_limit: 50,
          observability_run_event_limit: 200,
          observability_session_event_limit: 200,
          observability_index_key_limit: 500,
          observability_pending_event_queue_limit: 5_000,
          server_port: nil,
          server_host: nil,
          prompt: @workflow_prompt
        ],
        overrides
      )

    tracker_kind = Keyword.get(config, :tracker_kind)
    tracker_endpoint = Keyword.get(config, :tracker_endpoint)
    tracker_auth = Keyword.get(config, :tracker_auth)
    tracker_provider = Keyword.get(config, :tracker_provider)
    tracker_lifecycle = Keyword.get(config, :tracker_lifecycle)
    tracker_api_token = Keyword.get(config, :tracker_api_token)
    tracker_api_secret = Keyword.get(config, :tracker_api_secret)
    tracker_project_slug = Keyword.get(config, :tracker_project_slug)
    tracker_assignee = Keyword.get(config, :tracker_assignee)
    tracker_active_states = Keyword.get(config, :tracker_active_states)
    tracker_terminal_states = Keyword.get(config, :tracker_terminal_states)
    tracker_state_phase_map = Keyword.get(config, :tracker_state_phase_map)
    tracker_raw_state_by_route_key = Keyword.get(config, :tracker_raw_state_by_route_key)
    tracker_policy_by_route_key = Keyword.get(config, :tracker_policy_by_route_key)
    tracker_workflows_by_type = Keyword.get(config, :tracker_workflows_by_type)
    tracker_platform = Keyword.get(config, :tracker_platform)
    workflow_profile = Keyword.get(config, :workflow_profile)
    workflow_profile_kind = Keyword.get(config, :workflow_profile_kind)
    workflow_profile_version = Keyword.get(config, :workflow_profile_version)
    workflow_profile_options = Keyword.get(config, :workflow_profile_options)
    workflow_reconciliation = Keyword.get(config, :workflow_reconciliation)
    poll_interval_ms = Keyword.get(config, :poll_interval_ms)
    workspace_root = Keyword.get(config, :workspace_root)
    workspace_bootstrap_automation_from = Keyword.get(config, :workspace_bootstrap_automation_from)
    worker_ssh_hosts = Keyword.get(config, :worker_ssh_hosts)
    worker_max_concurrent_local_agents = Keyword.get(config, :worker_max_concurrent_local_agents)
    agent_runtime = Keyword.get(config, :agent_runtime)

    worker_max_concurrent_agents_per_host =
      Keyword.get(config, :worker_max_concurrent_agents_per_host)

    repo_path = Keyword.get(config, :repo_path)
    repo_base_branch = Keyword.get(config, :repo_base_branch)
    repo_remote_name = Keyword.get(config, :repo_remote_name)
    repo_remote_url = Keyword.get(config, :repo_remote_url)
    repo_branch_work_prefix = Keyword.get(config, :repo_branch_work_prefix)
    repo_provider_kind = Keyword.get(config, :repo_provider_kind)
    repo_provider_repository = Keyword.get(config, :repo_provider_repository)
    repo_provider_api_base_url = Keyword.get(config, :repo_provider_api_base_url)
    repo_provider_web_base_url = Keyword.get(config, :repo_provider_web_base_url)

    repo_provider_required_pr_label =
      Keyword.get(config, :repo_provider_required_pr_label)

    max_concurrent_agents = Keyword.get(config, :max_concurrent_agents)
    max_turns = Keyword.get(config, :max_turns)
    max_retry_backoff_ms = Keyword.get(config, :max_retry_backoff_ms)
    max_concurrent_agents_by_state = Keyword.get(config, :max_concurrent_agents_by_state)
    agent_credentials_enabled = Keyword.get(config, :agent_credentials_enabled)
    agent_credentials_store_root = Keyword.get(config, :agent_credentials_store_root)
    agent_credentials_allow_host_auth_reuse = Keyword.get(config, :agent_credentials_allow_host_auth_reuse)
    agent_credentials_rotation_strategy = Keyword.get(config, :agent_credentials_rotation_strategy)

    agent_credentials_max_concurrent_leases_per_account =
      Keyword.get(config, :agent_credentials_max_concurrent_leases_per_account)

    agent_credentials_lease_timeout_ms = Keyword.get(config, :agent_credentials_lease_timeout_ms)
    agent_credentials_default_ttl_ms = Keyword.get(config, :agent_credentials_default_ttl_ms)
    agent_credentials_exhausted_cooldown_ms = Keyword.get(config, :agent_credentials_exhausted_cooldown_ms)
    agent_credentials_daily_token_budget = Keyword.get(config, :agent_credentials_daily_token_budget)
    agent_quota_preflight = Keyword.get(config, :agent_quota_preflight)
    agent_quota_poller_enabled = Keyword.get(config, :agent_quota_poller_enabled)
    agent_quota_poll_interval_ms = Keyword.get(config, :agent_quota_poll_interval_ms)
    agent_quota_probe_timeout_ms = Keyword.get(config, :agent_quota_probe_timeout_ms)
    agent_quota_poll_providers = Keyword.get(config, :agent_quota_poll_providers)
    agent_provider_kind = Keyword.get(config, :agent_provider_kind)
    agent_provider_options = Keyword.get(config, :agent_provider_options)
    hook_after_create = Keyword.get(config, :hook_after_create)
    hook_before_run = Keyword.get(config, :hook_before_run)
    hook_after_run = Keyword.get(config, :hook_after_run)
    hook_before_remove = Keyword.get(config, :hook_before_remove)
    hook_timeout_ms = Keyword.get(config, :hook_timeout_ms)
    observability_enabled = Keyword.get(config, :observability_enabled)
    observability_refresh_ms = Keyword.get(config, :observability_refresh_ms)
    observability_render_interval_ms = Keyword.get(config, :observability_render_interval_ms)
    observability_file_enabled = Keyword.get(config, :observability_file_enabled)
    observability_console_enabled = Keyword.get(config, :observability_console_enabled)
    observability_log_format = Keyword.get(config, :observability_log_format)
    observability_summary_max_bytes = Keyword.get(config, :observability_summary_max_bytes)
    observability_global_event_limit = Keyword.get(config, :observability_global_event_limit)
    observability_issue_event_limit = Keyword.get(config, :observability_issue_event_limit)
    observability_run_event_limit = Keyword.get(config, :observability_run_event_limit)
    observability_session_event_limit = Keyword.get(config, :observability_session_event_limit)
    observability_index_key_limit = Keyword.get(config, :observability_index_key_limit)
    observability_pending_event_queue_limit = Keyword.get(config, :observability_pending_event_queue_limit)
    server_port = Keyword.get(config, :server_port)
    server_host = Keyword.get(config, :server_host)
    prompt = Keyword.get(config, :prompt)

    tracker_state_phase_map =
      resolve_tracker_state_phase_map(
        tracker_state_phase_map,
        tracker_kind,
        tracker_active_states,
        tracker_terminal_states
      )

    tracker_auth =
      merge_tracker_section(
        %{
          "api_key" => tracker_api_token,
          "api_secret" => tracker_api_secret
        },
        tracker_auth
      )

    tracker_provider =
      merge_tracker_section(
        %{
          "project_slug" => tracker_project_slug,
          "assignee" => tracker_assignee,
          "platform" => tracker_platform
        },
        tracker_provider
      )

    tracker_lifecycle =
      merge_tracker_section(
        %{
          "active_states" => tracker_active_states,
          "terminal_states" => tracker_terminal_states,
          "state_phase_map" => tracker_state_phase_map,
          "raw_state_by_route_key" => tracker_raw_state_by_route_key,
          "policy_by_route_key" => tracker_policy_by_route_key,
          "workflows_by_type" => tracker_workflows_by_type
        },
        tracker_lifecycle
      )

    workflow_profile =
      workflow_profile ||
        compact_test_map(%{
          "kind" => workflow_profile_kind,
          "version" => workflow_profile_version,
          "options" => workflow_profile_options
        })

    agent_provider_options = merge_agent_provider_options(agent_provider_kind, agent_provider_options)

    sections =
      [
        "---",
        workflow_yaml(workflow_profile, workflow_reconciliation),
        "tracker:",
        "  kind: #{yaml_value(tracker_kind)}",
        "  endpoint: #{yaml_value(tracker_endpoint)}",
        "  auth: #{yaml_value(tracker_auth)}",
        "  provider: #{yaml_value(tracker_provider)}",
        "  lifecycle: #{yaml_value(tracker_lifecycle)}",
        "polling:",
        "  interval_ms: #{yaml_value(poll_interval_ms)}",
        "workspace:",
        "  root: #{yaml_value(workspace_root)}",
        "  bootstrap_automation_from: #{yaml_value(workspace_bootstrap_automation_from)}",
        worker_yaml(worker_ssh_hosts, worker_max_concurrent_local_agents, worker_max_concurrent_agents_per_host),
        agent_runtime && "agent_runtime: #{yaml_value(agent_runtime)}",
        "repo:",
        repo_path && "  path: #{yaml_value(repo_path)}",
        "  base_branch: #{yaml_value(repo_base_branch)}",
        (repo_remote_name || repo_remote_url) && "  remote:",
        repo_remote_name && "    name: #{yaml_value(repo_remote_name)}",
        repo_remote_url && "    url: #{yaml_value(repo_remote_url)}",
        repo_branch_work_prefix && "  branch:",
        repo_branch_work_prefix && "    work_prefix: #{yaml_value(repo_branch_work_prefix)}",
        "  provider:",
        "    kind: #{yaml_value(repo_provider_kind)}",
        "    repository: #{yaml_value(repo_provider_repository)}",
        "    api_base_url: #{yaml_value(repo_provider_api_base_url)}",
        "    web_base_url: #{yaml_value(repo_provider_web_base_url)}",
        "    options:",
        "      required_pr_label: #{yaml_value(repo_provider_required_pr_label)}",
        agent_yaml(%{
          execution: %{
            max_concurrent_agents: max_concurrent_agents,
            max_turns: max_turns,
            max_retry_backoff_ms: max_retry_backoff_ms,
            max_concurrent_agents_by_state: max_concurrent_agents_by_state
          },
          credentials: %{
            enabled: agent_credentials_enabled,
            store_root: agent_credentials_store_root,
            allow_host_auth_reuse: agent_credentials_allow_host_auth_reuse,
            rotation_strategy: agent_credentials_rotation_strategy,
            max_concurrent_leases_per_account: agent_credentials_max_concurrent_leases_per_account,
            lease_timeout_ms: agent_credentials_lease_timeout_ms,
            default_ttl_ms: agent_credentials_default_ttl_ms,
            exhausted_cooldown_ms: agent_credentials_exhausted_cooldown_ms,
            daily_token_budget: agent_credentials_daily_token_budget
          },
          quota: %{
            preflight: agent_quota_preflight,
            poller_enabled: agent_quota_poller_enabled,
            poll_interval_ms: agent_quota_poll_interval_ms,
            probe_timeout_ms: agent_quota_probe_timeout_ms,
            poll_providers: agent_quota_poll_providers
          }
        }),
        "agent_provider:",
        "  kind: #{yaml_value(agent_provider_kind)}",
        "  options: #{yaml_value(agent_provider_options)}",
        hooks_yaml(
          hook_after_create,
          hook_before_run,
          hook_after_run,
          hook_before_remove,
          hook_timeout_ms
        ),
        observability_yaml(%{
          enabled: observability_enabled,
          refresh_ms: observability_refresh_ms,
          render_interval_ms: observability_render_interval_ms,
          file_enabled: observability_file_enabled,
          console_enabled: observability_console_enabled,
          log_format: observability_log_format,
          summary_max_bytes: observability_summary_max_bytes,
          global_event_limit: observability_global_event_limit,
          issue_event_limit: observability_issue_event_limit,
          run_event_limit: observability_run_event_limit,
          session_event_limit: observability_session_event_limit,
          index_key_limit: observability_index_key_limit,
          pending_event_queue_limit: observability_pending_event_queue_limit
        }),
        server_yaml(server_port, server_host),
        "---",
        prompt
      ]
      |> Enum.reject(&(&1 in [nil, ""]))

    Enum.join(sections, "\n") <> "\n"
  end

  defp yaml_value(value) when is_binary(value) do
    "\"" <> String.replace(value, "\"", "\\\"") <> "\""
  end

  defp yaml_value(value) when is_integer(value), do: to_string(value)
  defp yaml_value(true), do: "true"
  defp yaml_value(false), do: "false"
  defp yaml_value(nil), do: "null"

  defp yaml_value(values) when is_list(values) do
    "[" <> Enum.map_join(values, ", ", &yaml_value/1) <> "]"
  end

  defp yaml_value(values) when is_map(values) do
    "{" <>
      Enum.map_join(values, ", ", fn {key, value} ->
        "#{yaml_value(to_string(key))}: #{yaml_value(value)}"
      end) <> "}"
  end

  defp yaml_value(value), do: yaml_value(to_string(value))

  defp workflow_yaml(nil, nil), do: nil

  defp workflow_yaml(workflow_profile, workflow_reconciliation) do
    [
      "workflow:",
      workflow_profile && "  profile: #{yaml_value(workflow_profile)}",
      workflow_reconciliation && "  reconciliation: #{yaml_value(workflow_reconciliation)}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp resolve_tracker_state_phase_map(:default, tracker_kind, active_states, terminal_states) do
    case tracker_kind do
      "linear" ->
        %{
          "Backlog" => "backlog",
          "Todo" => "todo",
          "In Progress" => "in_progress",
          "In Review" => "human_review",
          "Merging" => "merging",
          "Rework" => "rework",
          "Done" => "done",
          "Closed" => "canceled",
          "Cancelled" => "canceled",
          "Canceled" => "canceled",
          "Duplicate" => "canceled"
        }

      _ ->
        derive_state_phase_map(active_states, terminal_states)
    end
  end

  defp resolve_tracker_state_phase_map(value, _tracker_kind, _active_states, _terminal_states),
    do: value

  defp merge_tracker_section(base_values, nil) when is_map(base_values), do: base_values

  defp merge_tracker_section(base_values, overrides)
       when is_map(base_values) and is_map(overrides) do
    Map.merge(base_values, Map.new(overrides, fn {key, value} -> {to_string(key), value} end))
  end

  defp compact_test_map(values) when is_map(values) do
    values
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> case do
      empty when map_size(empty) == 0 -> nil
      compacted -> compacted
    end
  end

  defp derive_state_phase_map(active_states, terminal_states) do
    active_map =
      active_states
      |> List.wrap()
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn
        {state_name, 0}, acc -> Map.put(acc, state_name, "todo")
        {state_name, _index}, acc -> Map.put(acc, state_name, "in_progress")
      end)

    terminal_map =
      terminal_states
      |> List.wrap()
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn
        {state_name, 0}, acc -> Map.put(acc, state_name, "done")
        {state_name, _index}, acc -> Map.put(acc, state_name, "canceled")
      end)

    Map.merge(active_map, terminal_map)
  end

  defp hooks_yaml(nil, nil, nil, nil, timeout_ms),
    do: "hooks:\n  timeout_ms: #{yaml_value(timeout_ms)}"

  defp hooks_yaml(
         hook_after_create,
         hook_before_run,
         hook_after_run,
         hook_before_remove,
         timeout_ms
       ) do
    [
      "hooks:",
      "  timeout_ms: #{yaml_value(timeout_ms)}",
      hook_entry("after_create", hook_after_create),
      hook_entry("before_run", hook_before_run),
      hook_entry("after_run", hook_after_run),
      hook_entry("before_remove", hook_before_remove)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp worker_yaml(ssh_hosts, max_concurrent_local_agents, max_concurrent_agents_per_host)
       when ssh_hosts in [nil, []] and is_nil(max_concurrent_local_agents) and
              is_nil(max_concurrent_agents_per_host),
       do: nil

  defp worker_yaml(ssh_hosts, max_concurrent_local_agents, max_concurrent_agents_per_host) do
    [
      "worker:",
      ssh_hosts not in [nil, []] && "  ssh_hosts: #{yaml_value(ssh_hosts)}",
      !is_nil(max_concurrent_local_agents) &&
        "  max_concurrent_local_agents: #{yaml_value(max_concurrent_local_agents)}",
      !is_nil(max_concurrent_agents_per_host) &&
        "  max_concurrent_agents_per_host: #{yaml_value(max_concurrent_agents_per_host)}"
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join("\n")
  end

  defp agent_yaml(settings) when is_map(settings) do
    [
      "agent:",
      "  execution:",
      "    max_concurrent_agents: #{yaml_value(settings.execution.max_concurrent_agents)}",
      "    max_turns: #{yaml_value(settings.execution.max_turns)}",
      "    max_retry_backoff_ms: #{yaml_value(settings.execution.max_retry_backoff_ms)}",
      "    max_concurrent_agents_by_state: #{yaml_value(settings.execution.max_concurrent_agents_by_state)}",
      agent_credentials_yaml(settings.credentials),
      agent_quota_yaml(settings.quota)
    ]
    |> Enum.join("\n")
  end

  defp agent_credentials_yaml(settings) when is_map(settings) do
    [
      "  credentials:",
      "    enabled: #{yaml_value(settings.enabled)}",
      "    store_root: #{yaml_value(settings.store_root)}",
      "    allow_host_auth_reuse: #{yaml_value(settings.allow_host_auth_reuse)}",
      "    rotation_strategy: #{yaml_value(settings.rotation_strategy)}",
      "    max_concurrent_leases_per_account: #{yaml_value(settings.max_concurrent_leases_per_account)}",
      "    lease_timeout_ms: #{yaml_value(settings.lease_timeout_ms)}",
      "    default_ttl_ms: #{yaml_value(settings.default_ttl_ms)}",
      "    exhausted_cooldown_ms: #{yaml_value(settings.exhausted_cooldown_ms)}",
      "    daily_token_budget: #{yaml_value(settings.daily_token_budget)}"
    ]
    |> Enum.join("\n")
  end

  defp agent_quota_yaml(settings) when is_map(settings) do
    [
      "  quota:",
      "    preflight: #{yaml_value(settings.preflight)}",
      "    poller_enabled: #{yaml_value(settings.poller_enabled)}",
      "    poll_interval_ms: #{yaml_value(settings.poll_interval_ms)}",
      "    probe_timeout_ms: #{yaml_value(settings.probe_timeout_ms)}",
      "    poll_providers: #{yaml_value(settings.poll_providers)}"
    ]
    |> Enum.join("\n")
  end

  defp observability_yaml(observability) when is_map(observability) do
    [
      "observability:",
      "  dashboard_enabled: #{yaml_value(observability.enabled)}",
      "  refresh_ms: #{yaml_value(observability.refresh_ms)}",
      "  render_interval_ms: #{yaml_value(observability.render_interval_ms)}",
      "  file_enabled: #{yaml_value(observability.file_enabled)}",
      "  console_enabled: #{yaml_value(observability.console_enabled)}",
      "  log_format: #{yaml_value(observability.log_format)}",
      "  summary_max_bytes: #{yaml_value(observability.summary_max_bytes)}",
      "  global_event_limit: #{yaml_value(observability.global_event_limit)}",
      "  issue_event_limit: #{yaml_value(observability.issue_event_limit)}",
      "  run_event_limit: #{yaml_value(observability.run_event_limit)}",
      "  session_event_limit: #{yaml_value(observability.session_event_limit)}",
      "  index_key_limit: #{yaml_value(observability.index_key_limit)}",
      "  pending_event_queue_limit: #{yaml_value(observability.pending_event_queue_limit)}"
    ]
    |> Enum.join("\n")
  end

  defp server_yaml(nil, nil), do: nil

  defp server_yaml(port, host) do
    [
      "server:",
      port && "  port: #{yaml_value(port)}",
      host && "  host: #{yaml_value(host)}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp hook_entry(_name, nil), do: nil

  defp hook_entry(name, command) when is_binary(command) do
    indented =
      command
      |> String.split("\n")
      |> Enum.map_join("\n", &("    " <> &1))

    "  #{name}: |\n#{indented}"
  end

  defp default_agent_provider_options do
    %{
      command: "codex app-server",
      approval_policy: "on-request",
      thread_sandbox: "workspace-write",
      turn_timeout_ms: 3_600_000,
      read_timeout_ms: 5_000,
      stall_timeout_ms: 300_000
    }
  end

  defp merge_agent_provider_options("codex", options) when is_map(options) do
    Map.merge(default_agent_provider_options(), options)
  end

  defp merge_agent_provider_options(_kind, options) when is_map(options), do: options
end
