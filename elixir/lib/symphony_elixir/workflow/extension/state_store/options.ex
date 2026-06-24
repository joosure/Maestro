defmodule SymphonyElixir.Workflow.Extension.StateStore.Options do
  @moduledoc """
  Option-boundary validation for the workflow extension state-store facade.
  """

  alias SymphonyElixir.Workflow.Extension.StateStore.Error

  @spec normalize(term()) :: {:ok, keyword()} | {:error, map()}
  def normalize(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, opts}
    else
      {:error, Error.build(:opts_not_keyword, opts)}
    end
  end

  def normalize(opts), do: {:error, Error.build(:opts_not_keyword, opts)}
end
