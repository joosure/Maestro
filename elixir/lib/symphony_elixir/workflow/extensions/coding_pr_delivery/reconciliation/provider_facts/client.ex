defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Client do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Options

  @spec map(atom(), map(), keyword(), Options.t()) :: {:ok, map()} | {:error, term()}
  def map(operation, repo, provider_opts, %Options{} = options) do
    case call(operation, repo, provider_opts, options) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      {:ok, payload} -> {:error, invalid_payload(operation, :map, payload)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec list(atom(), map(), keyword(), Options.t()) :: {:ok, [map()]} | {:error, term()}
  def list(operation, repo, provider_opts, %Options{} = options) do
    case call(operation, repo, provider_opts, options) do
      {:ok, payload} when is_list(payload) -> {:ok, payload}
      {:ok, payload} -> {:error, invalid_payload(operation, :list, payload)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec call(atom(), map(), keyword(), Options.t()) :: {:ok, term()} | {:error, term()}
  def call(operation, repo, provider_opts, %Options{} = options)
      when is_atom(operation) and is_map(repo) and is_list(provider_opts) do
    case Options.provider_fun(options, operation) do
      {:ok, provider_fun} -> invoke(provider_fun, operation, repo, provider_opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp invoke(provider_fun, operation, repo, provider_opts) do
    provider_fun.(repo, provider_opts)
    |> normalize_provider_result(operation)
  rescue
    error ->
      {:error, {:provider_facts_provider_callback_failed, callback_exception(operation, error)}}
  catch
    kind, reason ->
      {:error, {:provider_facts_provider_callback_failed, callback_caught(operation, kind, reason)}}
  end

  defp normalize_provider_result({:ok, payload}, _operation), do: {:ok, payload}
  defp normalize_provider_result({:error, reason}, _operation), do: {:error, reason}

  defp normalize_provider_result(:unsupported, operation) do
    {:error, {:unsupported_repo_provider_operation, %{operation: operation}}}
  end

  defp normalize_provider_result(other, operation) do
    {:error,
     {:invalid_repo_provider_result,
      %{
        operation: operation,
        result_type: Diagnostics.detailed_type_atom(other)
      }}}
  end

  defp invalid_payload(operation, expected, payload) do
    {:invalid_repo_provider_payload,
     %{
       operation: operation,
       expected: expected,
       payload_type: Diagnostics.detailed_type_atom(payload)
     }}
  end

  defp callback_exception(operation, error) do
    %{
      operation: operation,
      exception: inspect(error.__struct__)
    }
  end

  defp callback_caught(operation, kind, reason) do
    %{
      operation: operation,
      kind: kind,
      reason_type: Diagnostics.detailed_type_atom(reason)
    }
  end
end
