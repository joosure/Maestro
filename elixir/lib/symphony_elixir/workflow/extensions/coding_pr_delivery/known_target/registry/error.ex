defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry.Error do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics

  @invalid_options_code "invalid_coding_pr_delivery_known_target_registry_options"
  @invalid_attrs_code "invalid_coding_pr_delivery_known_target_registry_attrs"
  @invalid_issue_id_code "invalid_coding_pr_delivery_known_target_registry_issue_id"
  @invalid_storage_backend_code "invalid_coding_pr_delivery_known_target_registry_storage_backend"
  @storage_delete_failed_code "coding_pr_delivery_known_target_registry_storage_delete_failed"
  @error_code_key :code
  @json_error_code_key "code"

  @spec invalid_options(term()) :: map()
  def invalid_options(value) do
    %{
      code: @invalid_options_code,
      message: "Coding PR Delivery known-target registry options must be a keyword list.",
      reason: :opts_not_keyword,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec invalid_attrs(term()) :: map()
  def invalid_attrs(value) do
    %{
      code: @invalid_attrs_code,
      message: "Coding PR Delivery known-target registry requires map attrs.",
      reason: :attrs_not_map,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec invalid_issue_id(term()) :: map()
  def invalid_issue_id(value) do
    %{
      code: @invalid_issue_id_code,
      message: "Coding PR Delivery known-target registry requires a string issue id.",
      reason: :issue_id_not_string,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec invalid_storage_backend(term()) :: map()
  def invalid_storage_backend(value) do
    %{
      code: @invalid_storage_backend_code,
      message: "Coding PR Delivery known-target registry storage backend must be an atom module, :default, false, or nil.",
      reason: :invalid_storage_backend,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec storage_delete_failed(atom(), term()) :: map()
  def storage_delete_failed(operation, reason) when is_atom(operation) do
    %{
      code: @storage_delete_failed_code,
      message: "Coding PR Delivery known-target registry could not delete persisted targets.",
      reason: {:storage_delete_failed, operation},
      storage_reason_type: Diagnostics.type_name(reason)
    }
    |> put_storage_error_code(reason)
  end

  defp put_storage_error_code(error, reason) when is_map(reason) do
    case Map.get(reason, @error_code_key) || Map.get(reason, @json_error_code_key) do
      code when is_binary(code) -> Map.put(error, :storage_error_code, code)
      _other -> error
    end
  end

  defp put_storage_error_code(error, _reason), do: error
end
