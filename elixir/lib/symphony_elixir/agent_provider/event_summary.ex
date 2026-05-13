defmodule SymphonyElixir.AgentProvider.EventSummary do
  @moduledoc """
  Provider-neutral summary of an agent event or message.

  Provider adapters produce this shape after decoding their private protocol.
  Presentation layers then render it consistently through
  `SymphonyElixir.AgentProvider.MessagePresenter`.
  """

  @type category ::
          :message
          | :session
          | :turn
          | :tool
          | :approval
          | :stream
          | :usage
          | :error
          | :unknown

  @type severity :: :info | :success | :warning | :error

  @type t :: %__MODULE__{
          provider_kind: String.t() | nil,
          event: atom() | String.t() | nil,
          category: category(),
          severity: severity(),
          text: String.t() | nil,
          detail: String.t() | nil,
          payload: term(),
          raw: term(),
          metadata: map()
        }

  defstruct provider_kind: nil,
            event: nil,
            category: :message,
            severity: :info,
            text: nil,
            detail: nil,
            payload: nil,
            raw: nil,
            metadata: %{}

  @spec new(String.t() | nil, keyword()) :: t()
  def new(text, opts \\ []) do
    %__MODULE__{
      provider_kind: Keyword.get(opts, :provider_kind),
      event: Keyword.get(opts, :event),
      category: Keyword.get(opts, :category, :message),
      severity: Keyword.get(opts, :severity, :info),
      text: normalize_text(text),
      detail: normalize_text(Keyword.get(opts, :detail)),
      payload: Keyword.get(opts, :payload),
      raw: Keyword.get(opts, :raw),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @spec from_term(term(), keyword()) :: t()
  def from_term(term, opts \\ [])
  def from_term(%__MODULE__{} = summary, _opts), do: summary
  def from_term(nil, opts), do: new("no agent message yet", opts)
  def from_term(message, opts) when is_binary(message), do: new(message, opts)
  def from_term(message, opts), do: new(inspect(message, pretty: true, limit: 20), Keyword.put(opts, :raw, message))

  defp normalize_text(value) when is_binary(value), do: value
  defp normalize_text(nil), do: nil
  defp normalize_text(value), do: to_string(value)
end
