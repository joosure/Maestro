defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Runtime.Options do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics

  @invalid_options_code "invalid_coding_pr_delivery_extension_options"
  @reconciler_opts_key :reconciler_opts

  @type error :: %{
          required(:code) => String.t(),
          required(:message) => String.t(),
          required(:reason) => atom(),
          required(:value_type) => atom()
        }

  @spec reconciler_opts(term()) :: {:ok, keyword()} | {:error, error()}
  def reconciler_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
      |> Keyword.get(@reconciler_opts_key, [])
      |> resolve_reconciler_opts()
    else
      invalid_options(:extension_opts_not_keyword, opts)
    end
  end

  def reconciler_opts(opts), do: invalid_options(:extension_opts_not_keyword, opts)

  defp resolve_reconciler_opts(reconciler_opts) when is_function(reconciler_opts, 0) do
    reconciler_opts
    |> call_reconciler_opts()
    |> case do
      {:ok, resolved_opts} -> validate_reconciler_opts(resolved_opts)
      {:error, reason} -> invalid_options(reason, reconciler_opts)
    end
  end

  defp resolve_reconciler_opts(reconciler_opts), do: validate_reconciler_opts(reconciler_opts)

  defp call_reconciler_opts(reconciler_opts) do
    {:ok, reconciler_opts.()}
  rescue
    _error ->
      {:error, :reconciler_opts_function_failed}
  catch
    _kind, _reason ->
      {:error, :reconciler_opts_function_failed}
  end

  defp validate_reconciler_opts(reconciler_opts) do
    if Keyword.keyword?(reconciler_opts) do
      {:ok, reconciler_opts}
    else
      invalid_options(:reconciler_opts_not_keyword, reconciler_opts)
    end
  end

  defp invalid_options(reason, value) do
    {:error,
     %{
       code: @invalid_options_code,
       message: "Coding PR Delivery extension options are invalid.",
       reason: reason,
       value_type: Diagnostics.type_atom(value)
     }}
  end
end
