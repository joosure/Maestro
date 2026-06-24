defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Options do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProviderFactsDefaults

  defstruct env: nil,
            pr_view_fn: nil,
            pr_issue_comments_fn: nil,
            pr_review_comments_fn: nil,
            pr_reviews_fn: nil,
            pr_checks_fn: nil

  @type t :: %__MODULE__{
          env: map() | [{String.t(), String.t()}],
          pr_view_fn: function(),
          pr_issue_comments_fn: function(),
          pr_review_comments_fn: function(),
          pr_reviews_fn: function(),
          pr_checks_fn: function()
        }

  @provider_fun_options [
    :pr_view_fn,
    :pr_issue_comments_fn,
    :pr_review_comments_fn,
    :pr_reviews_fn,
    :pr_checks_fn
  ]

  @spec normalize(keyword()) :: {:ok, t()} | {:error, term()}
  def normalize(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      options = %__MODULE__{
        env: Keyword.get(opts, :env, System.get_env()),
        pr_view_fn: Keyword.get(opts, :pr_view_fn, &ProviderFactsDefaults.pr_view/2),
        pr_issue_comments_fn: Keyword.get(opts, :pr_issue_comments_fn, &ProviderFactsDefaults.pr_issue_comments/2),
        pr_review_comments_fn: Keyword.get(opts, :pr_review_comments_fn, &ProviderFactsDefaults.pr_review_comments/2),
        pr_reviews_fn: Keyword.get(opts, :pr_reviews_fn, &ProviderFactsDefaults.pr_reviews/2),
        pr_checks_fn: Keyword.get(opts, :pr_checks_fn, &ProviderFactsDefaults.pr_checks/2)
      }

      with :ok <- validate_env(options.env),
           :ok <- validate_provider_funs(options) do
        {:ok, options}
      end
    else
      {:error, invalid_options(:opts_not_keyword, opts)}
    end
  end

  def normalize(opts), do: {:error, invalid_options(:opts_not_keyword, opts)}

  @spec provider_fun(t(), atom()) :: {:ok, function()} | {:error, term()}
  def provider_fun(%__MODULE__{} = options, :pr_view), do: {:ok, options.pr_view_fn}
  def provider_fun(%__MODULE__{} = options, :pr_issue_comments), do: {:ok, options.pr_issue_comments_fn}
  def provider_fun(%__MODULE__{} = options, :pr_review_comments), do: {:ok, options.pr_review_comments_fn}
  def provider_fun(%__MODULE__{} = options, :pr_reviews), do: {:ok, options.pr_reviews_fn}
  def provider_fun(%__MODULE__{} = options, :pr_checks), do: {:ok, options.pr_checks_fn}

  def provider_fun(%__MODULE__{}, operation) do
    {:error, {:unsupported_repo_provider_operation, %{operation: operation}}}
  end

  defp validate_env(env) when is_map(env), do: :ok
  defp validate_env(env) when is_list(env), do: :ok
  defp validate_env(env), do: {:error, invalid_options(:env_not_map_or_list, env)}

  defp validate_provider_funs(%__MODULE__{} = options) do
    Enum.reduce_while(@provider_fun_options, :ok, fn key, :ok ->
      value = Map.fetch!(options, key)

      if is_function(value, 2) do
        {:cont, :ok}
      else
        {:halt, {:error, invalid_dependency(key, value)}}
      end
    end)
  end

  defp invalid_options(reason, value) do
    {:invalid_provider_facts_options,
     %{
       reason: reason,
       value_type: Diagnostics.detailed_type_atom(value)
     }}
  end

  defp invalid_dependency(option, value) do
    {:invalid_provider_facts_dependency,
     %{
       option: option,
       expected: "function/2",
       value_type: Diagnostics.detailed_type_atom(value)
     }}
  end
end
