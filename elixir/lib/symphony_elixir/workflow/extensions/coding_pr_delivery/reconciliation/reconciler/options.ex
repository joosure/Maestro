defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.Options do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ReconcilerDefaults, as: Defaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.Diagnostics

  defstruct raw_opts: [],
            change_proposal_facts_fn: nil,
            change_proposal_reference_fn: nil,
            defer_targeted_issue_ids_fn: nil,
            emit_event_fn: nil,
            fetch_issue_states_by_ids_fn: nil,
            fetch_issues_by_states_fn: nil,
            known_target_registry: nil,
            targeted_issue_ids: :unset,
            targeted_issue_ids_fn: nil

  @type t :: %__MODULE__{
          raw_opts: keyword(),
          change_proposal_facts_fn: function(),
          change_proposal_reference_fn: function() | nil,
          defer_targeted_issue_ids_fn: function() | nil,
          emit_event_fn: function(),
          fetch_issue_states_by_ids_fn: function(),
          fetch_issues_by_states_fn: function(),
          known_target_registry: term(),
          targeted_issue_ids: term(),
          targeted_issue_ids_fn: function() | nil
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
      change_proposal_facts_fn: Keyword.get(opts, :change_proposal_facts_fn, &Defaults.provider_facts/3),
      change_proposal_reference_fn: Keyword.get(opts, :change_proposal_reference_fn),
      defer_targeted_issue_ids_fn: Keyword.get(opts, :defer_targeted_issue_ids_fn),
      emit_event_fn: Keyword.get(opts, :emit_event_fn, &Defaults.emit_event/3),
      fetch_issue_states_by_ids_fn: Keyword.get(opts, :fetch_issue_states_by_ids_fn, &Defaults.fetch_issue_states_by_ids/2),
      fetch_issues_by_states_fn: Keyword.get(opts, :fetch_issues_by_states_fn, &Defaults.fetch_issues_by_states/2),
      known_target_registry: Keyword.get(opts, :known_target_registry),
      targeted_issue_ids: Keyword.get(opts, :targeted_issue_ids, :unset),
      targeted_issue_ids_fn: Keyword.get(opts, :targeted_issue_ids_fn)
    }
  end

  defp validate(%__MODULE__{} = options) do
    with :ok <- validate_fun(options.change_proposal_facts_fn, :change_proposal_facts_fn, 3),
         :ok <- validate_optional_fun(options.change_proposal_reference_fn, :change_proposal_reference_fn, 2),
         :ok <- validate_optional_fun(options.defer_targeted_issue_ids_fn, :defer_targeted_issue_ids_fn, [1, 2]),
         :ok <- validate_fun(options.emit_event_fn, :emit_event_fn, 3),
         :ok <- validate_fun(options.fetch_issue_states_by_ids_fn, :fetch_issue_states_by_ids_fn, 2),
         :ok <- validate_fun(options.fetch_issues_by_states_fn, :fetch_issues_by_states_fn, 2),
         :ok <- validate_optional_fun(options.targeted_issue_ids_fn, :targeted_issue_ids_fn, [0, 1]) do
      :ok
    end
  end

  defp validate_fun(fun, _name, arity) when is_function(fun, arity), do: :ok
  defp validate_fun(value, name, arity), do: {:error, Diagnostics.invalid_dependency(name, value, arity)}

  defp validate_optional_fun(nil, _name, _arity), do: :ok

  defp validate_optional_fun(value, name, arity_or_arities) do
    if supports_arity?(value, arity_or_arities) do
      :ok
    else
      {:error, Diagnostics.invalid_dependency(name, value, arity_or_arities)}
    end
  end

  defp supports_arity?(fun, arity) when is_integer(arity), do: is_function(fun, arity)
  defp supports_arity?(fun, arities) when is_list(arities), do: Enum.any?(arities, &is_function(fun, &1))
end
