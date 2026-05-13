defmodule SymphonyElixir.AgentProvider.Event do
  @moduledoc """
  Provider-neutral event shape emitted by concrete agent-provider protocol mappers.
  """

  @type t :: %__MODULE__{
          agent_provider_kind: String.t() | nil,
          event: atom() | String.t() | nil,
          payload: term(),
          raw: term(),
          run_id: String.t() | nil,
          session_id: String.t() | nil,
          timestamp: DateTime.t() | nil,
          metadata: map()
        }

  defstruct agent_provider_kind: nil,
            event: nil,
            payload: nil,
            raw: nil,
            run_id: nil,
            session_id: nil,
            timestamp: nil,
            metadata: %{}

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      agent_provider_kind: Keyword.get(opts, :agent_provider_kind),
      event: Keyword.get(opts, :event),
      payload: Keyword.get(opts, :payload),
      raw: Keyword.get(opts, :raw),
      run_id: Keyword.get(opts, :run_id),
      session_id: Keyword.get(opts, :session_id),
      timestamp: Keyword.get(opts, :timestamp),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @spec put_if_present(t(), atom(), term()) :: t()
  def put_if_present(%__MODULE__{} = event, _key, nil), do: event
  def put_if_present(%__MODULE__{} = event, _key, ""), do: event

  def put_if_present(%__MODULE__{} = event, key, value) when is_atom(key) do
    Map.put(event, key, value)
  end
end
