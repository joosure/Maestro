defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.TemplateCatalog.Assets do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Template

  @default_otp_app :symphony_elixir
  @relative_root Path.join(["workflow_extensions", "coding_pr_delivery", "templates"])
  @invalid_options_message "Coding PR Delivery template catalog options must be a keyword list."
  @invalid_asset_root_message "Coding PR Delivery template asset_root must be a non-empty string."
  @invalid_otp_app_message "Coding PR Delivery template otp_app must be an atom."

  @spec relative_root() :: Path.t()
  def relative_root, do: @relative_root

  @spec root!(term()) :: Path.t()
  def root!(opts \\ [])

  def root!(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      case Keyword.fetch(opts, :asset_root) do
        {:ok, asset_root} -> explicit_root!(asset_root)
        :error -> otp_priv_root!(opts)
      end
    else
      raise ArgumentError, @invalid_options_message
    end
  end

  def root!(_opts), do: raise(ArgumentError, @invalid_options_message)

  defp explicit_root!(asset_root) when is_binary(asset_root) and byte_size(asset_root) > 0 do
    Path.expand(asset_root)
  end

  defp explicit_root!(asset_root) do
    raise ArgumentError, "#{@invalid_asset_root_message} value_type=#{Diagnostics.type_name(asset_root)}"
  end

  defp otp_priv_root!(opts) do
    otp_app = Keyword.get(opts, :otp_app, @default_otp_app)

    if is_atom(otp_app) and not is_nil(otp_app) do
      Template.app_priv_root!(@relative_root, otp_app: otp_app)
    else
      raise ArgumentError, "#{@invalid_otp_app_message} value_type=#{Diagnostics.type_name(otp_app)}"
    end
  end
end
