defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.Validator do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.Error

  @spec validate_opts(term()) :: {:ok, keyword()} | {:error, map()}
  def validate_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, opts}
    else
      {:error, Error.invalid_options(opts)}
    end
  end

  def validate_opts(opts), do: {:error, Error.invalid_options(opts)}

  @spec validate_target(term()) :: :ok | {:error, map()}
  def validate_target(%KnownTarget{}), do: :ok
  def validate_target(target), do: {:error, Error.invalid_target(target)}

  @spec validate_targets(term()) :: :ok | {:error, map()}
  def validate_targets(targets) when is_list(targets) do
    case Enum.find(targets, &(not match?(%KnownTarget{}, &1))) do
      nil -> :ok
      target -> {:error, Error.invalid_target(target)}
    end
  end

  def validate_targets(targets), do: {:error, Error.invalid_targets(targets)}

  @spec validate_issue_id(term()) :: :ok | {:error, map()}
  def validate_issue_id(issue_id) when is_binary(issue_id), do: :ok
  def validate_issue_id(issue_id), do: {:error, Error.invalid_issue_id(issue_id)}
end
