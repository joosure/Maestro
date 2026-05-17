defmodule SymphonyElixir.RepoProvider.Command.Options do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Invocation

  @spec provider_opts(Invocation.t(), [atom()], keyword()) :: keyword()
  def provider_opts(%Invocation{} = invocation, keys, opts) when is_list(keys) and is_list(opts) do
    Keyword.merge(opts, invocation_values(invocation, keys))
  end

  @spec api_opts(Invocation.t(), keyword()) :: keyword()
  def api_opts(%Invocation{} = invocation, opts) when is_list(opts) do
    Keyword.merge(
      opts,
      endpoint: invocation.api_endpoint,
      method: invocation.api_method,
      fields: invocation.api_fields
    )
  end

  @spec land_watch_opts(Invocation.t(), keyword()) :: keyword()
  def land_watch_opts(%Invocation{} = invocation, opts) when is_list(opts) do
    opts
    |> maybe_put(:number, invocation.number)
    |> maybe_put(:poll_ms, invocation.poll_ms)
    |> maybe_put(:checks_appear_timeout_ms, invocation.checks_appear_timeout_ms)
  end

  @spec pr_checks_opts(Invocation.t(), keyword()) :: keyword()
  def pr_checks_opts(%Invocation{number: nil}, opts) when is_list(opts), do: opts

  def pr_checks_opts(%Invocation{number: number}, opts) when is_binary(number) and is_list(opts) do
    Keyword.put(opts, :number, number)
  end

  defp invocation_values(invocation, keys) do
    keys
    |> Enum.flat_map(fn key ->
      case Map.fetch!(invocation, key) do
        nil -> []
        value -> [{key, value}]
      end
    end)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, false), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
