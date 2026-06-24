defmodule SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.State do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.{FailureKey, FailureScope, RetryPolicy}

  defstruct counts: %{},
            threshold: nil,
            retry_policies: %{},
            resource_identity: nil,
            audit_fields: nil

  @type t :: %__MODULE__{
          counts: %{FailureKey.t() => non_neg_integer()},
          threshold: pos_integer(),
          retry_policies: %{String.t() => RetryPolicy.t()},
          resource_identity: function() | nil,
          audit_fields: function() | nil
        }

  @spec new!(keyword(), keyword()) :: t()
  def new!(opts, defaults) when is_list(opts) and is_list(defaults) do
    %__MODULE__{
      counts: %{},
      threshold: normalize_threshold!(Keyword.get(opts, :threshold, Keyword.fetch!(defaults, :threshold))),
      retry_policies:
        opts
        |> Keyword.get(:retry_policies, Keyword.fetch!(defaults, :retry_policies))
        |> RetryPolicy.normalize_many!(),
      resource_identity: normalize_fun!(Keyword.get(opts, :resource_identity, Keyword.get(defaults, :resource_identity)), 2, :resource_identity),
      audit_fields: normalize_fun!(Keyword.get(opts, :audit_fields, Keyword.get(defaults, :audit_fields)), 2, :audit_fields)
    }
  end

  @spec value(t(), atom()) :: term()
  def value(%__MODULE__{} = state, key) when is_atom(key), do: Map.get(state, key)

  @spec reset_counts(t()) :: t()
  def reset_counts(%__MODULE__{} = state), do: %{state | counts: %{}}

  @spec record_failure(t(), FailureKey.t()) :: {{pos_integer(), pos_integer()}, t()}
  def record_failure(%__MODULE__{} = state, %FailureKey{} = key) do
    count = Map.get(state.counts, key, 0) + 1
    {{count, state.threshold}, %{state | counts: Map.put(state.counts, key, count)}}
  end

  @spec reset_scope(t(), FailureScope.t()) :: t()
  def reset_scope(%__MODULE__{} = state, %FailureScope{} = scope) do
    counts =
      Map.reject(state.counts, fn
        {%FailureKey{scope: stored_scope}, _count} -> FailureScope.matches?(stored_scope, scope)
        _entry -> false
      end)

    %{state | counts: counts}
  end

  defp normalize_threshold!(threshold) when is_integer(threshold) and threshold > 0, do: threshold

  defp normalize_threshold!(_threshold) do
    raise ArgumentError, "typed tool failure retry threshold must be a positive integer"
  end

  defp normalize_fun!(nil, _arity, _field), do: nil
  defp normalize_fun!(fun, arity, _field) when is_function(fun, arity), do: fun

  defp normalize_fun!(_fun, _arity, field) do
    raise ArgumentError, "typed tool failure #{field} must be a function with the required arity"
  end
end
