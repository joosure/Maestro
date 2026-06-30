defmodule SymphonyElixir.Workflow.Template.Assets do
  @moduledoc """
  Path resolver for workflow template assets stored under OTP application `priv/`.

  This module owns only asset-root path mechanics. Template registries and
  workflow extensions own template metadata; plugin manifests or extension
  contributions own concrete template entries.
  """

  alias SymphonyElixir.Platform.PrivAssets

  @default_otp_app :symphony_elixir

  @spec app_priv_root!(Path.t(), keyword()) :: Path.t()
  def app_priv_root!(relative_dir, opts \\ []) when is_binary(relative_dir) and is_list(opts) do
    otp_app = Keyword.get(opts, :otp_app, @default_otp_app)
    PrivAssets.app_priv_root!(relative_dir, otp_app: otp_app)
  end
end
