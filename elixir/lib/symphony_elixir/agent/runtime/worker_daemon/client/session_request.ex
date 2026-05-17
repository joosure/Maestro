defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.Client.SessionRequest do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, Target}
  alias SymphonyWorkerDaemon.Auth.Defaults, as: AuthDefaults
  alias SymphonyWorkerDaemon.Protocol
  alias SymphonyWorkerDaemon.Protocol.Fields, as: ProtocolFields

  @protocol_version_key ProtocolFields.protocol_version()
  @request_id_key ProtocolFields.request_id()
  @run_id_key ProtocolFields.run_id()
  @caller_key ProtocolFields.caller()
  @command_key ProtocolFields.command()
  @workspace_key ProtocolFields.workspace()
  @env_key ProtocolFields.env()
  @resource_budget_key ProtocolFields.resource_budget()
  @timeout_policy_key ProtocolFields.timeout_policy()
  @required_features_key ProtocolFields.required_features()
  @dynamic_tool_bridge_key ProtocolFields.dynamic_tool_bridge()
  @mode_key ProtocolFields.mode()
  @argv_key ProtocolFields.argv()
  @cwd_key ProtocolFields.cwd()
  @workspace_path_key ProtocolFields.workspace_path()
  @remote_workspace_path_key ProtocolFields.remote_workspace_path()
  @workspace_root_key ProtocolFields.workspace_root()
  @provider_kind_key ProtocolFields.provider_kind()
  @worker_pool_key ProtocolFields.worker_pool()
  @owner_key ProtocolFields.owner()
  @tenant_id_key ProtocolFields.tenant_id()
  @deployment_id_key ProtocolFields.deployment_id()
  @startup_timeout_ms_key ProtocolFields.startup_timeout_ms()
  @idle_timeout_ms_key ProtocolFields.idle_timeout_ms()
  @session_timeout_ms_key ProtocolFields.session_timeout_ms()

  @spec create(CommandSpec.t(), Target.t(), keyword()) :: map()
  def create(%CommandSpec{} = command_spec, %Target{} = target, opts \\ []) do
    %{
      @protocol_version_key => Protocol.protocol_version(),
      @request_id_key => request_id(opts),
      @run_id_key => metadata_value(target.metadata, :run_id) || string_value(opts, :run_id),
      @caller_key => caller_payload(target, opts),
      @command_key => command_payload(command_spec),
      @workspace_key => workspace_payload(command_spec, target, opts),
      @env_key => merged_env(command_spec, target),
      @resource_budget_key => map_option(opts, :resource_budget),
      @timeout_policy_key => timeout_policy(opts),
      @required_features_key => list_option(opts, :worker_daemon_required_features),
      @dynamic_tool_bridge_key => dynamic_tool_bridge_payload(opts)
    }
    |> compact_map()
  end

  defp command_payload(%CommandSpec{argv: [_command | _args] = argv}) do
    %{@mode_key => "argv", @argv_key => argv}
  end

  defp command_payload(%CommandSpec{command: command}) when is_binary(command) do
    %{@mode_key => "shell", @command_key => command}
  end

  defp command_payload(%CommandSpec{}), do: %{@mode_key => "unset"}

  defp workspace_payload(%CommandSpec{} = command_spec, %Target{} = target, opts) do
    %{
      @cwd_key => command_spec.cwd || target.workspace_path,
      @workspace_path_key => target.workspace_path,
      @remote_workspace_path_key => target.remote_workspace_path,
      @workspace_root_key => string_value(opts, :workspace_root)
    }
    |> compact_map()
  end

  defp caller_payload(%Target{} = target, opts) do
    %{
      @provider_kind_key => metadata_value(target.metadata, :agent_provider_kind) || string_value(opts, :agent_provider_kind),
      @worker_pool_key => target.worker_pool,
      @owner_key => string_value(opts, :worker_daemon_owner) || AuthDefaults.default_owner(),
      @tenant_id_key => string_value(opts, :tenant_id),
      @deployment_id_key => string_value(opts, :deployment_id)
    }
    |> compact_map()
  end

  defp merged_env(%CommandSpec{} = command_spec, %Target{} = target) do
    target.env
    |> normalize_map()
    |> Map.merge(normalize_map(command_spec.env))
  end

  defp timeout_policy(opts) do
    %{
      @startup_timeout_ms_key => integer_option(opts, :startup_timeout_ms),
      @idle_timeout_ms_key => integer_option(opts, :idle_timeout_ms),
      @session_timeout_ms_key => integer_option(opts, :session_timeout_ms)
    }
    |> compact_map()
  end

  defp dynamic_tool_bridge_payload(opts) do
    cond do
      is_map(Keyword.get(opts, :dynamic_tool_bridge_spec)) ->
        Keyword.get(opts, :dynamic_tool_bridge_spec)

      is_map(Keyword.get(opts, :dynamic_tool_bridge_runtime)) ->
        opts
        |> Keyword.get(:dynamic_tool_bridge_runtime)
        |> Map.get(:daemon_bridge)

      true ->
        nil
    end
  end

  defp request_id(opts) do
    string_value(opts, :request_id) || Ecto.UUID.generate()
  end

  defp string_value(opts, key) when is_list(opts) do
    opts
    |> Keyword.get(key)
    |> optional_string()
  end

  defp integer_option(opts, key) when is_list(opts) do
    case Keyword.get(opts, key) do
      value when is_integer(value) and value > 0 -> value
      _value -> nil
    end
  end

  defp map_option(opts, key) when is_list(opts) do
    case Keyword.get(opts, key) do
      value when is_map(value) -> value
      _value -> %{}
    end
  end

  defp list_option(opts, key) when is_list(opts) do
    case Keyword.get(opts, key) do
      value when is_list(value) -> Enum.map(value, &to_string/1)
      _value -> []
    end
  end

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, Atom.to_string(key))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp optional_string(nil), do: nil

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> optional_string()
  defp optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp optional_string(_value), do: nil

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_map), do: %{}

  defp compact_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
