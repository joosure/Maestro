defmodule SymphonyElixir.Observability.EventStore.State do
  @moduledoc false

  alias SymphonyElixir.Observability.EventStore.{Buffer, Config, Index}

  defstruct next_seq: 1,
            config: %{},
            all_events: nil,
            issue_events: %{},
            issue_identifier_events: %{},
            run_events: %{},
            session_events: %{}

  @type record :: %{
          required(:seq) => pos_integer(),
          required(:payload) => map()
        }

  @type t :: %__MODULE__{
          next_seq: pos_integer(),
          config: Config.t(),
          all_events: Buffer.t(),
          issue_events: Index.t(),
          issue_identifier_events: Index.t(),
          run_events: Index.t(),
          session_events: Index.t()
        }

  @spec new(Config.t()) :: t()
  def new(config) do
    %__MODULE__{
      config: config,
      all_events: Buffer.new(config.global_event_limit)
    }
  end

  @spec append_event(t(), map()) :: t()
  def append_event(%__MODULE__{next_seq: seq, config: config} = state, event) when is_map(event) do
    record = %{seq: seq, payload: event}

    %{
      state
      | next_seq: seq + 1,
        all_events: Buffer.append(state.all_events, record),
        issue_events:
          Index.append(
            state.issue_events,
            Map.get(event, "issue_id"),
            record,
            config.issue_event_limit,
            config.index_key_limit
          ),
        issue_identifier_events:
          Index.append(
            state.issue_identifier_events,
            Map.get(event, "issue_identifier"),
            record,
            config.issue_event_limit,
            config.index_key_limit
          ),
        run_events:
          Index.append(
            state.run_events,
            Map.get(event, "run_id"),
            record,
            config.run_event_limit,
            config.index_key_limit
          ),
        session_events:
          Index.append(
            state.session_events,
            Map.get(event, "session_id"),
            record,
            config.session_event_limit,
            config.index_key_limit
          )
    }
  end

  @spec reconfigure(t(), Config.t()) :: t()
  def reconfigure(%__MODULE__{} = state, config) do
    %{
      state
      | config: config,
        all_events: Buffer.resize(state.all_events, config.global_event_limit),
        issue_events: Index.resize(state.issue_events, config.issue_event_limit, config.index_key_limit),
        issue_identifier_events:
          Index.resize(
            state.issue_identifier_events,
            config.issue_event_limit,
            config.index_key_limit
          ),
        run_events: Index.resize(state.run_events, config.run_event_limit, config.index_key_limit),
        session_events:
          Index.resize(
            state.session_events,
            config.session_event_limit,
            config.index_key_limit
          )
    }
  end
end
