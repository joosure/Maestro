defmodule SymphonyElixir.Agent.ExecutionPlan.StatusMachine.TransitionTable do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.StatusMachine, as: StatusMachineErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes

  @type status_validator :: (term() -> boolean())
  @type transition_kind :: :plan | :item

  @spec allowed?(map(), term(), term()) :: boolean()
  def allowed?(transitions, from_status, to_status) when is_binary(from_status) and is_binary(to_status) do
    to_status in Map.get(transitions, from_status, [])
  end

  def allowed?(_transitions, _from_status, _to_status), do: false

  @spec validate(map(), status_validator(), term(), term(), transition_kind()) :: :ok | {:error, map()}
  def validate(transitions, status_validator, from_status, to_status, transition_kind)
      when is_function(status_validator, 1) and transition_kind in [:plan, :item] do
    cond do
      not status_validator.(from_status) ->
        {:error, invalid_status_error(transition_kind, :from_status, from_status)}

      not status_validator.(to_status) ->
        {:error, invalid_status_error(transition_kind, :to_status, to_status)}

      allowed?(transitions, from_status, to_status) ->
        :ok

      true ->
        {:error, transition_forbidden_error(transition_kind, from_status, to_status)}
    end
  end

  defp invalid_status_error(transition_kind, status_role, status) do
    %{
      code: ValidationErrorCodes.invalid_enum(),
      message: "#{transition_label(transition_kind)} status must be an allowed value before transition validation.",
      status_kind: Atom.to_string(transition_kind),
      status_role: Atom.to_string(status_role),
      status: status
    }
  end

  defp transition_forbidden_error(:plan, from_status, to_status) do
    %{
      code: StatusMachineErrorCodes.plan_status_transition_forbidden(),
      message: "Plan status transition is not allowed.",
      from_status: from_status,
      to_status: to_status
    }
  end

  defp transition_forbidden_error(:item, from_status, to_status) do
    %{
      code: StatusMachineErrorCodes.item_status_transition_forbidden(),
      message: "Item status transition is not allowed.",
      from_status: from_status,
      to_status: to_status
    }
  end

  defp transition_label(:plan), do: "Plan"
  defp transition_label(:item), do: "Item"
end
