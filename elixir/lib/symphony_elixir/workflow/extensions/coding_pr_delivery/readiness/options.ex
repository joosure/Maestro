defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.Options do
  @moduledoc """
  Option-boundary validation for Coding PR Delivery readiness contributors.

  Readiness policies and recorders may be invoked by platform registries, tests,
  or future plugin manifests. This module keeps option shape validation local to
  the extension and prevents arbitrary lists from being treated as missing
  configuration.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics

  @type error :: %{
          required(:reason) => :opts_not_keyword,
          required(:value_type) => String.t()
        }

  @spec normalize(term()) :: {:ok, keyword()} | {:error, error()}
  def normalize(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, opts}
    else
      {:error, error(opts)}
    end
  end

  def normalize(opts), do: {:error, error(opts)}

  @spec keyword?(term()) :: boolean()
  def keyword?(opts), do: match?({:ok, _opts}, normalize(opts))

  defp error(opts) do
    %{
      reason: :opts_not_keyword,
      value_type: Diagnostics.type_name(opts)
    }
  end
end
