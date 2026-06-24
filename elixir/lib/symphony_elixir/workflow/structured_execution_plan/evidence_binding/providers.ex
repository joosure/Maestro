defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.Providers do
  @moduledoc """
  Aggregates extension-owned structured-plan evidence binding providers.
  """

  alias SymphonyElixir.Workflow.Extension.Contributions

  @contribution :structured_execution_plan_evidence_binding_providers

  @spec evidence_kind(String.t(), keyword()) :: String.t() | nil
  def evidence_kind(tool, opts \\ [])

  def evidence_kind(tool, opts) when is_binary(tool) and is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
      |> providers()
      |> Enum.find_value(&provider_evidence_kind(&1, tool, opts))
    else
      nil
    end
  end

  def evidence_kind(_tool, _opts), do: nil

  @spec identity_fields(String.t(), keyword()) :: [String.t()]
  def identity_fields(evidence_kind, opts \\ [])

  def identity_fields(evidence_kind, opts) when is_binary(evidence_kind) and is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
      |> providers()
      |> Enum.find_value([], &provider_identity_fields(&1, evidence_kind))
    else
      []
    end
  end

  def identity_fields(_evidence_kind, _opts), do: []

  @spec normalize(String.t(), String.t() | atom() | nil, term(), term(), map(), keyword()) :: {:ok, map()} | :unknown
  def normalize(evidence_kind, source_kind, source_context, arguments, payload, opts \\ [])

  def normalize(evidence_kind, source_kind, source_context, arguments, payload, opts)
      when is_binary(evidence_kind) and is_map(payload) and is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
      |> providers()
      |> Enum.reduce_while(nil, fn provider, _acc ->
        case {provider_identity_fields(provider, evidence_kind), provider_normalize(provider, evidence_kind, source_kind, source_context, arguments, payload)} do
          {_fields, {:ok, normalized}} -> {:halt, {:ok, normalized}}
          {fields, :unknown} when is_list(fields) -> {:halt, :unknown}
          {_fields, :unknown} -> {:cont, nil}
        end
      end)
      |> case do
        {:ok, normalized} -> {:ok, normalized}
        :unknown -> :unknown
        nil -> {:ok, %{}}
      end
    else
      :unknown
    end
  end

  def normalize(_evidence_kind, _source_kind, _source_context, _arguments, _payload, _opts), do: :unknown

  @spec valid?(String.t(), map(), keyword()) :: boolean()
  def valid?(evidence_kind, payload, opts \\ [])

  def valid?(evidence_kind, payload, opts) when is_binary(evidence_kind) and is_map(payload) and is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
      |> providers()
      |> Enum.reduce_while(:unknown, fn provider, _acc ->
        case provider_valid?(provider, evidence_kind, payload) do
          value when is_boolean(value) -> {:halt, value}
          :unknown -> {:cont, :unknown}
        end
      end)
      |> case do
        value when is_boolean(value) -> value
        :unknown -> true
      end
    else
      true
    end
  end

  def valid?(_evidence_kind, _payload, _opts), do: true

  @spec staleable_evidence_kinds(keyword()) :: [String.t()]
  def staleable_evidence_kinds(opts \\ []) when is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
      |> providers()
      |> Enum.flat_map(&provider_staleable_evidence_kinds/1)
      |> Enum.uniq()
    else
      []
    end
  end

  defp providers(opts), do: Contributions.list!(@contribution, opts)

  defp provider_evidence_kind(provider, tool, opts) do
    case safe_call(provider, :evidence_kind, [tool, opts]) do
      evidence_kind when is_binary(evidence_kind) -> evidence_kind
      _other -> nil
    end
  end

  defp provider_identity_fields(provider, evidence_kind) do
    case safe_call(provider, :identity_fields, [evidence_kind]) do
      fields when is_list(fields) -> fields
      _other -> nil
    end
  end

  defp provider_normalize(provider, evidence_kind, source_kind, source_context, arguments, payload) do
    case safe_call(provider, :normalize, [evidence_kind, source_kind, source_context, arguments, payload]) do
      {:ok, normalized} when is_map(normalized) -> {:ok, normalized}
      _other -> :unknown
    end
  end

  defp provider_valid?(provider, evidence_kind, payload) do
    case safe_call(provider, :valid?, [evidence_kind, payload]) do
      value when is_boolean(value) -> value
      _other -> :unknown
    end
  end

  defp provider_staleable_evidence_kinds(provider) do
    case safe_call(provider, :staleable_evidence_kinds, []) do
      values when is_list(values) -> Enum.filter(values, &is_binary/1)
      _other -> []
    end
  end

  defp safe_call(provider, callback, args) do
    apply(provider, callback, args)
  rescue
    _error -> :unknown
  catch
    _kind, _reason -> :unknown
  end
end
