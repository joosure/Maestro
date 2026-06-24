defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Arguments do
  @moduledoc """
  Raw argument boundary for workflow structured execution-plan tools.

  Public functions parse external Dynamic Tool argument maps into small,
  atom-keyed command structs. Runtime modules should consume the parsed command
  maps instead of re-reading raw string-keyed input.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Contract

  @type snapshot_args ::
          %{required(:plan_id) => String.t()}
          | %{required(:run_id) => String.t(), required(:workflow_profile) => map(), required(:route_key) => String.t()}
  @type upsert_args ::
          {:create, map()}
          | {:merge_items, String.t(), pos_integer(), [map()]}
  @type update_item_args :: %{
          required(:plan_id) => String.t(),
          required(:item_id) => String.t(),
          required(:status) => String.t(),
          required(:plan_revision) => pos_integer()
        }
  @type render_workpad_args :: %{
          required(:plan_id) => String.t(),
          required(:plan_revision) => pos_integer(),
          required(:mode) => String.t(),
          required(:heading) => String.t() | nil,
          required(:max_items) => pos_integer() | nil
        }

  @spec snapshot(term()) :: {:ok, snapshot_args()} | {:error, term()}
  def snapshot(arguments) when is_map(arguments) do
    with :ok <- reject_unknown_fields(arguments, [Fields.plan_id(), Fields.run_id(), Fields.workflow_profile(), Fields.route_key()]) do
      plan_id = optional_string(arguments, Fields.plan_id())
      run_id = optional_string(arguments, Fields.run_id())
      workflow_profile = Map.get(arguments, Fields.workflow_profile())
      route_key = optional_string(arguments, Fields.route_key())

      cond do
        is_binary(plan_id) ->
          {:ok, %{plan_id: plan_id}}

        is_binary(run_id) and is_map(workflow_profile) and is_binary(route_key) ->
          {:ok, %{run_id: run_id, workflow_profile: workflow_profile, route_key: route_key}}

        true ->
          {:error, {:invalid_arguments, "Plan snapshot requires plan_id or run_id, workflow_profile, and route_key."}}
      end
    end
  end

  def snapshot(_arguments), do: {:error, {:invalid_arguments, "Expected an object for plan snapshot."}}

  @spec upsert(term()) :: {:ok, upsert_args()} | {:error, term()}
  def upsert(arguments) when is_map(arguments) do
    with :ok <- reject_unknown_fields(arguments, [Contract.plan_arg(), Fields.plan_id(), Contract.plan_revision_arg(), Fields.items()]) do
      cond do
        is_map(Map.get(arguments, Contract.plan_arg())) ->
          {:ok, {:create, Map.fetch!(arguments, Contract.plan_arg())}}

        true ->
          with {:ok, plan_id} <- required_string(arguments, Fields.plan_id()),
               {:ok, plan_revision} <- required_positive_integer(arguments, Contract.plan_revision_arg()),
               {:ok, items} <- required_item_list(arguments, Fields.items()) do
            {:ok, {:merge_items, plan_id, plan_revision, items}}
          end
      end
    end
  end

  def upsert(_arguments), do: {:error, {:invalid_arguments, "Expected an object for plan upsert."}}

  @spec update_item(term()) :: {:ok, update_item_args()} | {:error, term()}
  def update_item(arguments) when is_map(arguments) do
    with :ok <-
           reject_unknown_fields(arguments, [
             Fields.plan_id(),
             AgentFields.item_id(),
             AgentFields.status(),
             Contract.plan_revision_arg(),
             Contract.note_arg(),
             Contract.evidence_id_arg()
           ]),
         {:ok, plan_id} <- required_string(arguments, Fields.plan_id()),
         {:ok, item_id} <- required_string(arguments, AgentFields.item_id()),
         {:ok, status} <- required_string(arguments, AgentFields.status()),
         {:ok, plan_revision} <- required_positive_integer(arguments, Contract.plan_revision_arg()) do
      {:ok, %{plan_id: plan_id, item_id: item_id, status: status, plan_revision: plan_revision}}
    end
  end

  def update_item(_arguments), do: {:error, {:invalid_arguments, "Expected an object for plan item update."}}

  @spec render_workpad(term()) :: {:ok, render_workpad_args()} | {:error, term()}
  def render_workpad(arguments) when is_map(arguments) do
    with :ok <-
           reject_unknown_fields(arguments, [
             Fields.plan_id(),
             Contract.plan_revision_arg(),
             Contract.mode_arg(),
             Contract.heading_arg(),
             Contract.max_items_arg()
           ]),
         {:ok, plan_id} <- required_string(arguments, Fields.plan_id()),
         {:ok, plan_revision} <- required_positive_integer(arguments, Contract.plan_revision_arg()),
         {:ok, mode} <- required_string(arguments, Contract.mode_arg()),
         {:ok, max_items} <- optional_positive_integer(arguments, Contract.max_items_arg()) do
      {:ok,
       %{
         plan_id: plan_id,
         plan_revision: plan_revision,
         mode: mode,
         heading: optional_string(arguments, Contract.heading_arg()),
         max_items: max_items
       }}
    end
  end

  def render_workpad(_arguments), do: {:error, {:invalid_arguments, "Expected an object for plan Workpad rendering."}}

  @spec preview_mode() :: String.t()
  defdelegate preview_mode, to: Contract

  @spec render_opts(render_workpad_args()) :: keyword()
  def render_opts(args) when is_map(args) do
    []
    |> Keyword.put(:mode, args.mode)
    |> maybe_put(:heading, args.heading)
    |> maybe_put(:max_items, args.max_items)
  end

  defp required_string(map, key) do
    case optional_string(map, key) do
      value when is_binary(value) -> {:ok, value}
      _value -> {:error, {:invalid_arguments, "Missing required string field #{key}."}}
    end
  end

  defp optional_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      value when is_integer(value) ->
        Integer.to_string(value)

      _value ->
        nil
    end
  end

  defp required_positive_integer(map, key) do
    case Map.get(map, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _value -> {:error, {:invalid_arguments, "#{key} must be a positive integer."}}
    end
  end

  defp optional_positive_integer(map, key) do
    case Map.get(map, key) do
      nil -> {:ok, nil}
      value when is_integer(value) and value > 0 -> {:ok, value}
      _value -> {:error, {:invalid_arguments, "#{key} must be a positive integer."}}
    end
  end

  defp required_item_list(map, key) do
    case Map.get(map, key) do
      values when is_list(values) ->
        if values != [] and Enum.all?(values, &is_map/1) do
          {:ok, values}
        else
          {:error, {:invalid_arguments, "#{key} must be a non-empty array of item objects."}}
        end

      _value ->
        {:error, {:invalid_arguments, "#{key} must be a non-empty array of item objects."}}
    end
  end

  defp reject_unknown_fields(map, allowed_fields) do
    unknown_fields = map |> Map.keys() |> Enum.reject(&(&1 in allowed_fields))

    if unknown_fields == [] do
      :ok
    else
      {:error, {:invalid_arguments, "Unsupported argument field(s): #{Enum.join(unknown_fields, ", ")}."}}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
