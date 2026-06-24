defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.OneShotHostDeps do
  @moduledoc false

  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Workflow
  alias SymphonyElixir.Workflow.Extension.Runtime.Context, as: RuntimeContext
  alias SymphonyElixir.Workflow.Extension.Runtime.Projection, as: RuntimeProjection
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Deps
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Runtime.Input, as: RuntimeInput
  alias SymphonyElixir.Workflow.Template, as: Templates

  @spec runtime() :: Deps.t()
  def runtime do
    %{
      monotonic_time_ms: fn -> System.monotonic_time(:millisecond) end,
      workflow_file_path: &Workflow.workflow_file_path/0,
      set_workflow_file_path: &Workflow.set_workflow_file_path/1,
      workflow_file_env: fn -> Application.fetch_env(:symphony_elixir, :workflow_file_path) end,
      restore_workflow_file_env: &restore_workflow_file_env/1,
      start_known_target_registry: fn settings ->
        KnownTarget.Registry.start_link(name: nil, workflow_scope: workflow_scope(settings))
      end,
      stop_known_target_registry: fn pid ->
        if Process.alive?(pid), do: GenServer.stop(pid)
        :ok
      end,
      resolve_template: &Templates.resolve/1,
      file_regular?: &File.regular?/1,
      validate_config: &SymphonyElixir.Config.validate!/0,
      settings: &SymphonyElixir.Config.settings!/0,
      initial_state: &initial_runtime_state/1,
      reconcile: &reconcile_runtime_input/3,
      fetch_issue_states_by_ids: fn tracker, issue_ids, fetch_opts ->
        Tracker.fetch_issue_states_by_ids(tracker, issue_ids, fetch_opts)
      end,
      update_issue_state: fn tracker, issue_id, state_name, update_opts ->
        Tracker.update_issue_state(tracker, issue_id, state_name, update_opts)
      end,
      issue_events: fn issue_id -> EventStore.recent_issue_events(%{issue_id: issue_id}, limit: 50) end,
      recent_events: fn -> EventStore.recent_events(limit: 50) end
    }
  end

  defp reconcile_runtime_input(settings, runtime_input, opts)
       when is_map(settings) and is_map(runtime_input) and is_list(opts) do
    runtime = RuntimeProjection.new(runtime_input)
    result = Reconciliation.reconcile_runtime(settings, RuntimeInput.from_projection(runtime, CodingPrDelivery.id()), opts)

    put_extension_state(runtime_input, result.extension_state)
  end

  defp put_extension_state(runtime_input, extension_state) when is_map(runtime_input) and is_map(extension_state) do
    workflow_extensions =
      runtime_input
      |> Map.get(:workflow_extensions, %{})
      |> case do
        extensions when is_map(extensions) -> extensions
        _extensions -> %{}
      end

    Map.put(runtime_input, :workflow_extensions, Map.put(workflow_extensions, CodingPrDelivery.id(), extension_state))
  end

  defp initial_runtime_state(settings) when is_map(settings) do
    %{
      running: %{},
      claimed: MapSet.new(),
      max_concurrent_agents: max_concurrent_agents(settings),
      workflow_extensions: %{}
    }
  end

  defp workflow_scope(settings) when is_map(settings), do: RuntimeContext.new!(settings, %{}).workflow_scope

  defp restore_workflow_file_env({:ok, path}) when is_binary(path), do: Workflow.set_workflow_file_path(path)
  defp restore_workflow_file_env(:error), do: Workflow.clear_workflow_file_path()

  defp max_concurrent_agents(settings) do
    settings
    |> settings_agent()
    |> agent_execution()
    |> execution_max_concurrent_agents()
  end

  defp settings_agent(%{agent: agent}), do: agent
  defp settings_agent(%{"agent" => agent}), do: agent
  defp settings_agent(_settings), do: nil

  defp agent_execution(%{execution: execution}), do: execution
  defp agent_execution(%{"execution" => execution}), do: execution
  defp agent_execution(_agent), do: nil

  defp execution_max_concurrent_agents(%{max_concurrent_agents: value}), do: value
  defp execution_max_concurrent_agents(%{"max_concurrent_agents" => value}), do: value
  defp execution_max_concurrent_agents(_execution), do: nil
end
