defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ConfigValidator do
  @moduledoc """
  Settings validation adapter for the Coding PR Delivery extension facade.

  The extension facade exposes the platform callback; this module owns the
  delegation to the extension's current configuration model.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config, as: ReconciliationConfig

  @spec validate_settings(map(), term()) :: :ok | {:error, term()}
  def validate_settings(settings, profile_context) when is_map(settings) do
    ReconciliationConfig.validate_settings(settings, profile_context)
  end
end
