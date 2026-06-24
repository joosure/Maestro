defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Error do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics

  @invalid_known_target_code "invalid_coding_pr_delivery_known_target"

  @spec invalid_options(term()) :: map()
  def invalid_options(value) do
    %{
      code: @invalid_known_target_code,
      message: "Coding PR Delivery known-target options must be a keyword list.",
      reason: :opts_not_keyword,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec invalid_attrs(term()) :: map()
  def invalid_attrs(value) do
    %{
      code: @invalid_known_target_code,
      message: "Coding PR Delivery known-target attrs must be a map.",
      reason: :attrs_not_map,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec invalid_record(term(), atom()) :: map()
  def invalid_record(value, role) when is_atom(role) do
    %{
      code: @invalid_known_target_code,
      message: "Coding PR Delivery known-target merge requires KnownTarget records.",
      reason: {:invalid_known_target_record, role},
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec invalid_now_ms(term()) :: map()
  def invalid_now_ms(value) do
    %{
      code: @invalid_known_target_code,
      message: "Coding PR Delivery known-target timestamps must be integer milliseconds.",
      reason: :invalid_now_ms,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec invalid_signature(term()) :: map()
  def invalid_signature(reason) do
    %{
      code: @invalid_known_target_code,
      message: "Coding PR Delivery known-target observed signature must be JSON-compatible.",
      reason: {:invalid_last_observed_signature, reason}
    }
  end

  @spec missing_issue_id() :: map()
  def missing_issue_id do
    %{
      code: @invalid_known_target_code,
      message: "Coding PR Delivery known-target requires an issue id.",
      reason: :missing_issue_id
    }
  end

  @spec missing_reference() :: map()
  def missing_reference do
    %{
      code: @invalid_known_target_code,
      message: "Coding PR Delivery known-target requires a change-proposal reference.",
      reason: :missing_change_proposal_reference
    }
  end
end
