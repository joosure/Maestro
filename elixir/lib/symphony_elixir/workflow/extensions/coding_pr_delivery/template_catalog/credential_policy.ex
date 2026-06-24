defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.TemplateCatalog.CredentialPolicy do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.Ref, as: CredentialRef
  alias SymphonyElixir.Workflow.Extension.Diagnostics

  @type credential_resolver :: (String.t(), String.t() -> String.t() | nil)
  @invalid_options_message "Coding PR Delivery credential policy options must be a keyword list."
  @invalid_resolver_message "Coding PR Delivery credential_ref_fn must be a function/2 or nil."

  @spec credential_ref(map(), keyword()) :: String.t() | nil
  def credential_ref(entry, opts) when is_map(entry) do
    opts = validate_opts!(opts)

    case entry do
      %{agent_provider_kind: provider_kind, credential_account_id: account_id}
      when is_binary(provider_kind) and is_binary(account_id) ->
        opts
        |> resolver!()
        |> case do
          nil -> nil
          resolver -> resolver.(provider_kind, account_id)
        end

      _entry ->
        nil
    end
  end

  def credential_ref(_entry, opts) do
    validate_opts!(opts)
    nil
  end

  defp validate_opts!(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
    else
      raise ArgumentError, @invalid_options_message
    end
  end

  defp validate_opts!(_opts), do: raise(ArgumentError, @invalid_options_message)

  defp resolver!(opts) do
    case Keyword.get(opts, :credential_ref_fn, &CredentialRef.for_account/2) do
      nil ->
        nil

      resolver when is_function(resolver, 2) ->
        resolver

      resolver ->
        raise ArgumentError, "#{@invalid_resolver_message} value_type=#{Diagnostics.type_name(resolver)}"
    end
  end
end
