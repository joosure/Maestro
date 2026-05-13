defmodule SymphonyElixir.AgentProvider do
  @moduledoc """
  Facade for the configured AI coding agent provider.
  """

  alias SymphonyElixir.AgentProvider.Capabilities
  alias SymphonyElixir.AgentProvider.Config
  alias SymphonyElixir.AgentProvider.ConfigResolver
  alias SymphonyElixir.AgentProvider.EventSummary
  alias SymphonyElixir.AgentProvider.MessageRouting
  alias SymphonyElixir.AgentProvider.Registry
  alias SymphonyElixir.AgentProvider.Session
  alias SymphonyElixir.AgentProvider.SessionLifecycle
  alias SymphonyElixir.AgentProvider.TurnResult
  alias SymphonyElixir.AgentProvider.WorkspacePreparation

  @spec default_kind() :: String.t()
  def default_kind, do: Registry.default_kind()

  @spec current_kind(keyword()) :: String.t()
  def current_kind(opts \\ []), do: ConfigResolver.current_kind(opts)

  @spec adapter(keyword()) :: module()
  def adapter(opts \\ []), do: ConfigResolver.adapter(opts)

  @spec adapter_for(term()) :: module() | nil
  def adapter_for(kind), do: ConfigResolver.adapter_for(kind)

  @spec supported_kinds() :: [String.t()]
  def supported_kinds, do: Registry.supported_kinds()

  @spec validate_config(term()) :: :ok | {:error, term()}
  def validate_config(config) do
    config = Config.new(config)

    case adapter_for(config.kind) do
      nil -> {:error, {:unsupported_agent_provider_kind, config.kind}}
      adapter -> adapter.validate_config(config)
    end
  end

  @spec validate_options(term(), term()) :: :ok | {:error, term()}
  def validate_options(kind, options) when is_map(options) do
    case adapter_for(kind) do
      nil -> :ok
      adapter -> adapter.validate_options(options)
    end
  end

  def validate_options(_kind, _options), do: {:error, :invalid_agent_provider_options}

  @spec defaults(term()) :: map()
  def defaults(kind) do
    case adapter_for(kind) do
      nil -> %{}
      adapter -> adapter.defaults()
    end
  end

  @spec finalize_options(term(), map()) :: map()
  def finalize_options(kind, options) when is_map(options) do
    case adapter_for(kind) do
      nil -> options
      adapter -> adapter.defaults() |> Map.merge(Config.new(%{options: options}).options) |> adapter.finalize_options()
    end
  end

  @spec start_session(Path.t(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  def start_session(workspace, opts \\ []), do: SessionLifecycle.start_session(workspace, opts)

  @spec run_turn(term(), String.t(), map(), keyword()) :: {:ok, TurnResult.t()} | {:error, term()}
  def run_turn(session, prompt, issue, opts \\ []), do: SessionLifecycle.run_turn(session, prompt, issue, opts)

  @spec stop_session(term(), keyword()) :: :ok | {:error, term()}
  def stop_session(session, opts \\ []), do: SessionLifecycle.stop_session(session, opts)

  @spec session_stop_options(term(), term(), keyword()) :: keyword()
  def session_stop_options(result, issue, opts \\ []), do: SessionLifecycle.session_stop_options(result, issue, opts)

  @spec failed_session_stop_options(term(), String.t(), keyword()) :: keyword()
  def failed_session_stop_options(issue, error, opts \\ []) when is_binary(error),
    do: SessionLifecycle.failed_session_stop_options(issue, error, opts)

  @spec summarize_message(term(), keyword()) :: EventSummary.t()
  def summarize_message(message, opts \\ []), do: MessageRouting.summarize_message(message, opts)

  @spec present_message(term(), keyword()) :: String.t()
  def present_message(message, opts \\ []), do: MessageRouting.present_message(message, opts)

  @spec session_log_event?(String.t(), String.t(), keyword()) :: boolean()
  def session_log_event?(component, event, opts \\ []), do: MessageRouting.session_log_event?(component, event, opts)

  @spec workspace_automation_destination_dir(keyword()) :: String.t()
  def workspace_automation_destination_dir(opts \\ []) do
    adapter(opts).workspace_automation_destination_dir()
  end

  @spec prepare_workspace(Path.t(), keyword()) :: :ok | {:error, term()}
  def prepare_workspace(workspace, opts \\ []), do: WorkspacePreparation.prepare_workspace(workspace, opts)

  @spec capabilities(keyword()) :: [String.t()]
  def capabilities(opts \\ []) do
    opts
    |> adapter()
    |> Capabilities.adapter_capabilities()
  end

  @spec supports?(String.t(), keyword()) :: boolean()
  def supports?(capability, opts \\ []) when is_binary(capability) do
    opts
    |> capabilities()
    |> Enum.member?(capability)
  end
end
