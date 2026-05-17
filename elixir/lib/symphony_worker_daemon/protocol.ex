defmodule SymphonyWorkerDaemon.Protocol do
  @moduledoc false

  alias SymphonyWorkerDaemon.Protocol.{Features, Paths, Request, Response, Validation}

  @protocol_version "2026-05-02"
  @supported_features Features.supported()
  @session_required_features Features.session_required()

  @type health_response :: %{
          required(:status) => String.t(),
          required(:protocol_version) => String.t(),
          optional(:daemon_version) => String.t(),
          optional(:worker_id) => String.t(),
          optional(:daemon_instance_id) => String.t(),
          optional(:worker_profile_version) => String.t(),
          optional(:capacity) => map(),
          optional(:features) => [String.t()],
          optional(:capabilities) => [map()]
        }

  @type create_response :: %{
          required(:session_id) => String.t(),
          optional(:worker_id) => String.t(),
          optional(:daemon_instance_id) => String.t(),
          optional(:lease_id) => String.t(),
          optional(:status) => String.t(),
          optional(:metadata) => map()
        }

  @type session_summary :: %{
          required(:session_id) => String.t(),
          optional(:status) => String.t(),
          optional(:run_id) => String.t(),
          optional(:owner) => String.t(),
          optional(:tenant_id) => String.t(),
          optional(:provider_kind) => String.t(),
          optional(:worker_pool) => String.t(),
          optional(:lease_id) => String.t(),
          optional(:cwd) => String.t(),
          optional(:os_pid) => pos_integer(),
          optional(:exit_status) => integer(),
          optional(:started_at_ms) => integer(),
          optional(:updated_at_ms) => integer()
        }

  @type session_event :: %{
          required(:event_id) => non_neg_integer(),
          required(:type) => String.t(),
          optional(:stream) => String.t(),
          optional(:data) => String.t(),
          optional(:timestamp_ms) => integer()
        }

  @spec protocol_version() :: String.t()
  def protocol_version, do: @protocol_version

  @spec daemon_version() :: String.t()
  def daemon_version do
    case Application.spec(:symphony_elixir, :vsn) do
      nil -> "unknown"
      version -> List.to_string(version)
    end
  end

  @spec supported_features() :: [String.t()]
  def supported_features, do: @supported_features

  @spec session_required_features() :: [String.t()]
  def session_required_features, do: @session_required_features

  @spec base_path() :: String.t()
  defdelegate base_path(), to: Paths

  @spec health_path() :: String.t()
  defdelegate health_path(), to: Paths

  @spec sessions_path() :: String.t()
  defdelegate sessions_path(), to: Paths

  @spec sessions_path(map() | keyword()) :: String.t()
  defdelegate sessions_path(filters), to: Paths

  @spec session_path(String.t()) :: String.t()
  defdelegate session_path(session_id), to: Paths

  @spec input_path(String.t()) :: String.t()
  defdelegate input_path(session_id), to: Paths

  @spec stop_path(String.t()) :: String.t()
  defdelegate stop_path(session_id), to: Paths

  @spec cleanup_path(String.t()) :: String.t()
  defdelegate cleanup_path(session_id), to: Paths

  @spec events_path(String.t()) :: String.t()
  defdelegate events_path(session_id), to: Paths

  @spec events_path(String.t(), map() | keyword()) :: String.t()
  defdelegate events_path(session_id, filters), to: Paths

  @spec input_request(iodata(), keyword()) :: map()
  def input_request(data, opts \\ []) do
    Request.input(data, opts, @protocol_version)
  end

  @spec stop_request(keyword()) :: map()
  def stop_request(opts \\ []) do
    Request.stop(opts, @protocol_version)
  end

  @spec cleanup_request(keyword()) :: map()
  def cleanup_request(opts \\ []) do
    Request.cleanup(opts, @protocol_version)
  end

  @spec validate_create_request(map()) :: :ok | {:error, term()}
  @spec validate_create_request(map(), [String.t()]) :: :ok | {:error, term()}
  @spec validate_create_request(map(), [String.t()], keyword()) :: :ok | {:error, term()}
  def validate_create_request(request, supported_features \\ @supported_features, opts \\ []) do
    Validation.validate_create_request(request, supported_features, validation_opts(opts))
  end

  @spec validate_input_request(map(), keyword()) :: :ok | {:error, term()}
  def validate_input_request(request, opts \\ []) do
    Validation.validate_input_request(request, validation_opts(opts))
  end

  @spec validate_stop_request(map(), keyword()) :: :ok | {:error, term()}
  def validate_stop_request(request, opts \\ []) do
    Validation.validate_stop_request(request, validation_opts(opts))
  end

  @spec validate_cleanup_request(map(), keyword()) :: :ok | {:error, term()}
  def validate_cleanup_request(request, opts \\ []) do
    Validation.validate_cleanup_request(request, validation_opts(opts))
  end

  @spec normalize_health_response(term()) :: {:ok, health_response()} | {:error, term()}
  defdelegate normalize_health_response(payload), to: Response

  @spec normalize_create_response(term()) :: {:ok, create_response()} | {:error, term()}
  defdelegate normalize_create_response(payload), to: Response

  @spec normalize_status(term()) :: {:ok, String.t()} | {:error, term()}
  defdelegate normalize_status(payload), to: Response

  @spec normalize_session_list_response(term()) :: {:ok, [session_summary()]} | {:error, term()}
  defdelegate normalize_session_list_response(payload), to: Response

  @spec normalize_session_events_response(term()) :: {:ok, [session_event()]} | {:error, term()}
  defdelegate normalize_session_events_response(payload), to: Response

  @spec terminal_status?(String.t()) :: boolean()
  defdelegate terminal_status?(status), to: Response

  @spec error_reason(atom(), pos_integer() | nil, term()) :: term()
  defdelegate error_reason(operation, status, payload), to: Response

  defp validation_opts(opts) when is_list(opts), do: Keyword.put(opts, :protocol_version, @protocol_version)
end
