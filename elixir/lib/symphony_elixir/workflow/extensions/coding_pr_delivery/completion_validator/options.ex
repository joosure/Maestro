defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.Options do
  @moduledoc """
  Public option boundary for Coding PR Delivery completion validation.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics

  @invalid_options_code :invalid_completion_validator_options
  @invalid_input_code :invalid_completion_validator_input

  @type error :: %{
          required(:code) => atom(),
          required(:reason) => atom(),
          required(:value_type) => String.t()
        }

  @spec normalize(term()) :: {:ok, keyword()} | {:error, error()}
  def normalize(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, opts}
    else
      {:error, error(:opts_not_keyword, "non_keyword_list")}
    end
  end

  def normalize(opts), do: {:error, error(:opts_not_keyword, Diagnostics.type_name(opts))}

  @spec invalid_issue(term()) :: error()
  def invalid_issue(issue), do: error(@invalid_input_code, :issue_not_map, Diagnostics.type_name(issue))

  @spec invalid_evidence(term()) :: error()
  def invalid_evidence(evidence),
    do: error(@invalid_input_code, :evidence_not_map, Diagnostics.type_name(evidence))

  @spec invalid_capabilities(term()) :: error()
  def invalid_capabilities(capabilities),
    do: error(@invalid_input_code, :capabilities_not_map, Diagnostics.type_name(capabilities))

  defp error(reason, value_type), do: error(@invalid_options_code, reason, value_type)

  defp error(code, reason, value_type) do
    %{
      code: code,
      reason: reason,
      value_type: value_type
    }
  end
end
