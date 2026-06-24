defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Deps do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics

  @type t :: %{
          required(:monotonic_time_ms) => (-> integer()),
          required(:workflow_file_path) => (-> Path.t()),
          required(:set_workflow_file_path) => (Path.t() -> :ok),
          required(:workflow_file_env) => (-> {:ok, Path.t()} | :error),
          required(:restore_workflow_file_env) => ({:ok, Path.t()} | :error -> :ok),
          required(:start_known_target_registry) => (map() -> GenServer.on_start()),
          required(:stop_known_target_registry) => (pid() -> :ok),
          required(:resolve_template) => (String.t() -> {:ok, Path.t()} | {:error, term()}),
          required(:file_regular?) => (Path.t() -> boolean()),
          required(:validate_config) => (-> :ok | {:error, term()}),
          required(:settings) => (-> map()),
          required(:initial_state) => (map() -> map()),
          required(:reconcile) => (map(), map(), keyword() -> map()),
          required(:fetch_issue_states_by_ids) => (map(), [String.t()], keyword() -> {:ok, [term()]} | {:error, term()}),
          required(:update_issue_state) => (map(), String.t(), String.t(), keyword() -> :ok | {:error, term()}),
          required(:issue_events) => (String.t() -> [map()]),
          required(:recent_events) => (-> [map()])
        }

  @required_functions [
    monotonic_time_ms: 0,
    workflow_file_path: 0,
    set_workflow_file_path: 1,
    workflow_file_env: 0,
    restore_workflow_file_env: 1,
    start_known_target_registry: 1,
    stop_known_target_registry: 1,
    resolve_template: 1,
    file_regular?: 1,
    validate_config: 0,
    settings: 0,
    initial_state: 1,
    reconcile: 3,
    fetch_issue_states_by_ids: 3,
    update_issue_state: 4,
    issue_events: 1,
    recent_events: 0
  ]

  @spec validate(term()) :: {:ok, t()} | {:error, map()}
  def validate(%{} = deps) do
    case Enum.find(@required_functions, fn {key, arity} -> not valid_function?(deps, key, arity) end) do
      nil ->
        {:ok, deps}

      {key, arity} ->
        {:error,
         %{
           code: :invalid_one_shot_deps,
           field: key,
           expected: "function/#{arity}",
           value_type: Diagnostics.type_name(Map.get(deps, key))
         }}
    end
  end

  def validate(deps) do
    {:error, %{code: :invalid_one_shot_deps, value_type: Diagnostics.type_name(deps)}}
  end

  defp valid_function?(deps, key, arity), do: is_function(Map.get(deps, key), arity)
end
