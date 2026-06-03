defmodule SymphonyElixir.Release.CredentialPreflight.ProviderPlan do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.{Registry, ReleaseCredentialPreflight}

  @spec fetch(String.t()) :: {:ok, module()} | {:error, String.t()}
  def fetch(provider_kind) do
    case Registry.fetch(provider_kind) do
      nil ->
        {:error, unsupported_message(provider_kind)}

      adapter ->
        case adapter_plan(adapter, provider_kind) do
          {:ok, provider_plan} -> {:ok, provider_plan}
          :unsupported -> {:error, unsupported_message(provider_kind)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @spec login_plan(module(), String.t(), map()) ::
          {:ok, ReleaseCredentialPreflight.LoginPlan.t()} | {:error, String.t()}
  def login_plan(provider_plan, account_id, env_map) do
    ReleaseCredentialPreflight.login_plan(provider_plan, account_id, env_map)
  end

  @spec verify_opts(module(), map(), map()) :: {:ok, keyword()} | {:error, String.t()}
  def verify_opts(provider_plan, env_map, settings) do
    ReleaseCredentialPreflight.verify_opts(provider_plan, env_map, settings)
  end

  defp adapter_plan(adapter, provider_kind) when is_atom(adapter) and is_binary(provider_kind) do
    if adapter_callback_exported?(adapter, :release_credential_preflight_plan, 0) do
      adapter
      |> adapter_plan_module(provider_kind)
      |> validate_adapter_plan(adapter, provider_kind)
    else
      :unsupported
    end
  end

  defp adapter_plan_module(adapter, _provider_kind) do
    adapter.release_credential_preflight_plan()
  rescue
    exception ->
      {:invalid_plan, "release_credential_preflight_plan/0 raised #{Exception.message(exception)}"}
  catch
    kind, reason ->
      {:invalid_plan, "release_credential_preflight_plan/0 threw #{kind} #{inspect(reason)}"}
  end

  defp validate_adapter_plan(:unsupported, _adapter, _provider_kind), do: :unsupported

  defp validate_adapter_plan({:invalid_plan, reason}, adapter, provider_kind) do
    {:error, invalid_plan_message(provider_kind, adapter, reason)}
  end

  defp validate_adapter_plan(plan_module, adapter, provider_kind) when is_atom(plan_module) do
    case ReleaseCredentialPreflight.validate_plan_module(plan_module, provider_kind) do
      :ok -> {:ok, plan_module}
      {:error, reason} -> {:error, invalid_plan_message(provider_kind, adapter, reason)}
    end
  end

  defp validate_adapter_plan(plan_module, adapter, provider_kind) do
    {:error,
     invalid_plan_message(
       provider_kind,
       adapter,
       "expected module or :unsupported from release_credential_preflight_plan/0, got #{inspect(plan_module)}"
     )}
  end

  defp adapter_callback_exported?(adapter, function, arity) do
    Code.ensure_loaded?(adapter) and function_exported?(adapter, function, arity)
  end

  defp unsupported_message(provider_kind) do
    "container managed credential preflight supports #{supported_provider_kinds()}, got #{provider_kind}"
  end

  defp invalid_plan_message(provider_kind, adapter, reason) do
    "invalid release credential preflight plan for #{provider_kind} from #{inspect(adapter)}: #{reason}"
  end

  defp supported_provider_kinds do
    Registry.adapters()
    |> Enum.flat_map(fn {provider_kind, adapter} ->
      case adapter_plan(adapter, provider_kind) do
        {:ok, _plan} -> [provider_kind]
        _unsupported_or_error -> []
      end
    end)
    |> Enum.sort()
    |> Enum.join(", ")
  end
end
