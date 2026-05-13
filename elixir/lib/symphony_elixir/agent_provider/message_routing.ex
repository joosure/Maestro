defmodule SymphonyElixir.AgentProvider.MessageRouting do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.ConfigResolver
  alias SymphonyElixir.AgentProvider.EventSummary
  alias SymphonyElixir.AgentProvider.MessagePresenter
  alias SymphonyElixir.AgentProvider.Registry

  @spec summarize_message(term(), keyword()) :: EventSummary.t()
  def summarize_message(%EventSummary{} = summary, _opts), do: summary

  def summarize_message(message, opts) do
    message
    |> adapter_for_message(opts)
    |> Kernel.apply(:summarize_message, [message])
  end

  @spec present_message(term(), keyword()) :: String.t()
  def present_message(message, opts) do
    message
    |> summarize_message(opts)
    |> MessagePresenter.present()
  end

  @spec session_log_event?(String.t(), String.t(), keyword()) :: boolean()
  def session_log_event?(component, event, opts) when is_binary(component) and is_binary(event) do
    opts
    |> session_log_adapters()
    |> Enum.any?(& &1.session_log_event?(component, event))
  end

  def session_log_event?(_component, _event, _opts), do: false

  defp session_log_adapters(opts) do
    case Keyword.get(opts, :kind) do
      nil ->
        Registry.adapters()
        |> Map.values()
        |> Enum.uniq()

      _kind ->
        [ConfigResolver.adapter(opts)]
    end
  end

  defp adapter_for_message(message, opts) do
    cond do
      explicit_provider_opts?(opts) ->
        ConfigResolver.adapter(opts)

      provider_kind = message_provider_kind(message) ->
        ConfigResolver.adapter_for(provider_kind) || ConfigResolver.adapter(opts)

      true ->
        ConfigResolver.adapter(opts)
    end
  end

  defp explicit_provider_opts?(opts) do
    Keyword.has_key?(opts, :kind) or Keyword.has_key?(opts, :agent_provider_config)
  end

  defp message_provider_kind(%EventSummary{provider_kind: provider_kind}) when is_binary(provider_kind), do: provider_kind

  defp message_provider_kind(%{} = message) do
    Map.get(message, :agent_provider_kind) ||
      Map.get(message, "agent_provider_kind") ||
      Map.get(message, :provider_kind) ||
      Map.get(message, "provider_kind") ||
      nested_message_provider_kind(message)
  end

  defp message_provider_kind(_message), do: nil

  defp nested_message_provider_kind(%{message: nested}), do: message_provider_kind(nested)
  defp nested_message_provider_kind(%{"message" => nested}), do: message_provider_kind(nested)
  defp nested_message_provider_kind(_message), do: nil
end
