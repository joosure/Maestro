defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.Error do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics

  @invalid_options_code "invalid_coding_pr_delivery_known_target_storage_options"
  @invalid_target_code "invalid_coding_pr_delivery_known_target_storage_target"
  @invalid_targets_code "invalid_coding_pr_delivery_known_target_storage_targets"
  @invalid_issue_id_code "invalid_coding_pr_delivery_known_target_storage_issue_id"
  @invalid_backend_code "invalid_coding_pr_delivery_known_target_storage_backend"
  @invalid_backend_contract_code "invalid_coding_pr_delivery_known_target_storage_backend_contract"

  @spec invalid_options(term()) :: map()
  def invalid_options(value) do
    %{
      code: @invalid_options_code,
      message: "Coding PR Delivery known-target storage options must be a keyword list.",
      reason: :opts_not_keyword,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec invalid_target(term()) :: map()
  def invalid_target(value) do
    %{
      code: @invalid_target_code,
      message: "Coding PR Delivery known-target storage requires KnownTarget records.",
      reason: :invalid_known_target_storage_target,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec invalid_targets(term()) :: map()
  def invalid_targets(value) do
    %{
      code: @invalid_targets_code,
      message: "Coding PR Delivery known-target storage requires a list of KnownTarget records.",
      reason: :invalid_known_target_storage_targets,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec invalid_issue_id(term()) :: map()
  def invalid_issue_id(value) do
    %{
      code: @invalid_issue_id_code,
      message: "Coding PR Delivery known-target storage requires a string issue id.",
      reason: :invalid_known_target_storage_issue_id,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec invalid_backend(term(), atom()) :: map()
  def invalid_backend(value, reason) when is_atom(reason) do
    %{
      code: @invalid_backend_code,
      message: "Coding PR Delivery known-target storage backend must be a loaded module.",
      reason: reason,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec invalid_backend_contract(module(), [{atom(), non_neg_integer()}]) :: map()
  def invalid_backend_contract(backend, missing_callbacks) when is_atom(backend) and is_list(missing_callbacks) do
    %{
      code: @invalid_backend_contract_code,
      message: "Coding PR Delivery known-target storage backend does not implement the storage contract.",
      reason: :missing_storage_backend_callbacks,
      backend_module: inspect(backend),
      missing_callbacks: Enum.map(missing_callbacks, &callback_name/1)
    }
  end

  defp callback_name({name, arity}) when is_atom(name) and is_integer(arity), do: "#{name}/#{arity}"
end
