defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Transition.Options do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.TransitionDefaults, as: Defaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Transition.Diagnostics

  defstruct raw_opts: [],
            dry_run?: false,
            fetch_issue_states_by_ids_fn: nil,
            update_issue_state_fn: nil

  @type t :: %__MODULE__{
          raw_opts: keyword(),
          dry_run?: boolean(),
          fetch_issue_states_by_ids_fn: function(),
          update_issue_state_fn: function()
        }

  @spec normalize(term()) :: {:ok, t()} | {:error, map()}
  def normalize(opts) do
    with true <- Keyword.keyword?(opts),
         options = build(opts),
         :ok <- validate(options) do
      {:ok, options}
    else
      false -> {:error, Diagnostics.invalid_options(opts)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build(opts) do
    %__MODULE__{
      raw_opts: opts,
      dry_run?: Keyword.get(opts, :dry_run?, false),
      fetch_issue_states_by_ids_fn: Keyword.get(opts, :fetch_issue_states_by_ids_fn, &Defaults.fetch_issue_states_by_ids/2),
      update_issue_state_fn: Keyword.get(opts, :update_issue_state_fn, &Defaults.update_issue_state/3)
    }
  end

  defp validate(%__MODULE__{} = options) do
    with :ok <- validate_boolean(options.dry_run?, :dry_run?),
         :ok <- validate_fun(options.fetch_issue_states_by_ids_fn, :fetch_issue_states_by_ids_fn, 2),
         :ok <- validate_fun(options.update_issue_state_fn, :update_issue_state_fn, 3) do
      :ok
    end
  end

  defp validate_boolean(value, _name) when is_boolean(value), do: :ok
  defp validate_boolean(value, :dry_run?), do: {:error, Diagnostics.invalid_dry_run(value)}

  defp validate_fun(fun, _name, arity) when is_function(fun, arity), do: :ok
  defp validate_fun(value, name, arity), do: {:error, Diagnostics.invalid_dependency(name, value, arity)}
end
