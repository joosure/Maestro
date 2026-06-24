defmodule SymphonyElixir.Release.CredentialPreflight do
  @moduledoc """
  Release-only managed credential preflight.

  This module intentionally sets the process-global workflow file path before
  loading settings. The release runner then starts the service with the same
  workflow path, so credential initialization and runtime credential reads use
  the same store configuration.
  """

  alias SymphonyElixir.Agent.Credential.Accounts
  alias SymphonyElixir.Agent.Credential.Store.Selection, as: CredentialSelection
  alias SymphonyElixir.AgentProvider.Kinds, as: AgentProviderKinds
  alias SymphonyElixir.Config
  alias SymphonyElixir.Platform.Env
  alias SymphonyElixir.Release.CredentialPreflight.ProviderPlan
  alias SymphonyElixir.Release.WorkflowSource
  alias SymphonyElixir.Workflow
  alias SymphonyElixir.Workflow.Template, as: WorkflowTemplates

  @preflight_disabled_values ~w(0 false no off disabled)
  @preflight_enabled_values ~w(1 true yes on auto)
  @preflight_env "SYMPHONY_AGENT_CREDENTIAL_PREFLIGHT"
  @account_id_env "SYMPHONY_AGENT_CREDENTIAL_ACCOUNT_ID"

  @type deps :: %{
          required(:accounts_login) => (String.t(), String.t(), keyword(), map() ->
                                          {:ok, map()} | {:error, term()}),
          required(:accounts_verify) => (String.t(), String.t(), keyword(), map() ->
                                           {:ok, map()} | {:error, term()}),
          required(:resolve_template) => (String.t() -> {:ok, Path.t()} | {:error, term()}),
          required(:set_workflow_file_path) => (Path.t() -> :ok | {:error, term()}),
          required(:settings) => (-> {:ok, map()} | {:error, term()}),
          optional(:log) => (String.t() -> term())
        }

  @spec preflight_env() :: String.t()
  def preflight_env, do: @preflight_env

  @spec account_id_env() :: String.t()
  def account_id_env, do: @account_id_env

  @spec run_from_env(map(), deps()) :: :ok | {:error, String.t()}
  def run_from_env(env_map, deps \\ runtime_deps()) when is_map(env_map) do
    with {:ok, mode} <- preflight_mode(env_map),
         :continue <- maybe_continue_preflight(mode),
         {:ok, workflow_path} <- preflight_workflow_path(env_map, deps),
         :ok <- set_preflight_workflow_path(workflow_path, deps),
         {:ok, settings} <- preflight_settings(deps),
         {:ok, request} <- preflight_request(settings, env_map, mode) do
      request
      |> run_preflight(settings, deps)
      |> wrap_preflight_result()
    else
      :skip ->
        :ok

      {:skip, message} ->
        log_preflight(deps, message)
        :ok

      {:error, message} when is_binary(message) ->
        {:error, "Managed credential preflight failed: #{message}"}
    end
  end

  defp runtime_deps do
    %{
      accounts_login: &Accounts.login/4,
      accounts_verify: &Accounts.verify/4,
      resolve_template: &WorkflowTemplates.resolve/1,
      set_workflow_file_path: &Workflow.set_workflow_file_path/1,
      settings: &Config.settings/0,
      log: fn message -> IO.puts(:stderr, message) end
    }
  end

  defp wrap_preflight_result(:ok), do: :ok

  defp wrap_preflight_result({:error, message}) when is_binary(message),
    do: {:error, "Managed credential preflight failed: #{message}"}

  defp preflight_mode(env_map) do
    value =
      env_map
      |> Env.value(@preflight_env, "off")
      |> String.downcase()

    cond do
      value in @preflight_disabled_values ->
        {:ok, :off}

      value in @preflight_enabled_values ->
        {:ok, :auto}

      value == "required" ->
        {:ok, :required}

      true ->
        {:error, "invalid #{@preflight_env}=#{inspect(value)}; use off, auto, or required"}
    end
  end

  defp maybe_continue_preflight(:off), do: :skip
  defp maybe_continue_preflight(_mode), do: :continue

  defp preflight_workflow_path(env_map, deps) do
    case WorkflowSource.from_env(env_map) do
      {:template, template} ->
        template
        |> deps.resolve_template.()
        |> case do
          {:ok, path} -> {:ok, path}
          {:error, reason} -> {:error, format_reason(reason)}
        end

      {:workflow_path, workflow_path} ->
        {:ok, workflow_path}
    end
  end

  defp set_preflight_workflow_path(workflow_path, deps) do
    case deps.set_workflow_file_path.(workflow_path) do
      :ok -> :ok
      {:error, reason} -> {:error, format_reason(reason)}
      other -> {:error, inspect(other)}
    end
  end

  defp preflight_settings(deps) do
    case deps.settings.() do
      {:ok, settings} when is_map(settings) ->
        {:ok, settings}

      {:error, reason} ->
        {:error, Config.format_error(reason)}

      other ->
        {:error, "unexpected settings result: #{inspect(other)}"}
    end
  end

  defp preflight_request(settings, env_map, mode) do
    provider_kind = provider_kind(settings)
    credential_ref = credential_ref(settings)

    cond do
      is_nil(credential_ref) and mode == :auto ->
        {:skip, "Managed credential preflight skipped: workflow has no agent_provider.options.credential_ref."}

      is_nil(credential_ref) ->
        {:error, "#{@preflight_env}=required but workflow has no agent_provider.options.credential_ref"}

      provider_kind in [nil, ""] ->
        {:error, "workflow agent_provider.kind is missing"}

      not credentials_enabled?(settings) ->
        {:error, "workflow uses #{credential_ref}, but agent.credentials.enabled is false"}

      true ->
        with {:ok, account_id} <- credential_account_id(provider_kind, credential_ref, env_map),
             {:ok, provider_plan} <- ProviderPlan.fetch(provider_kind),
             {:ok, login_plan} <- ProviderPlan.login_plan(provider_plan, account_id, env_map),
             {:ok, verify_opts} <- ProviderPlan.verify_opts(provider_plan, env_map, settings) do
          {:ok,
           %{
             account_id: account_id,
             credential_ref: credential_ref,
             credential_hint: login_plan.credential_hint,
             login_opts: login_plan.login_opts,
             provider_kind: provider_kind,
             token_env: login_plan.token_env,
             verify_opts: verify_opts
           }}
        end
    end
  end

  defp provider_kind(settings) do
    settings
    |> Env.nested([:agent_provider, :kind])
    |> Env.normalize_string()
    |> AgentProviderKinds.normalize()
  end

  defp credential_ref(settings) do
    settings
    |> Env.nested([:agent_provider, :options, :credential_ref])
    |> Env.normalize_string()
  end

  defp credentials_enabled?(settings) do
    settings
    |> Env.nested([:agent, :credentials, :enabled])
    |> Kernel.==(true)
  end

  defp credential_account_id(provider_kind, credential_ref, env_map) do
    case CredentialSelection.parse_credential_ref(provider_kind, credential_ref) do
      {:ok, {:account, account_id}} ->
        {:ok, account_id}

      {:ok, :pool} ->
        case Env.value(env_map, @account_id_env) do
          nil ->
            {:error, "#{credential_ref} selects a credential pool; set #{@account_id_env} for container preflight"}

          account_id ->
            {:ok, account_id}
        end

      {:error, reason} ->
        {:error, format_reason(reason)}
    end
  end

  defp run_preflight(request, settings, deps) do
    log_preflight(deps, "Running managed credential preflight for #{credential_label(request)}.")

    with :ok <- maybe_login_preflight(request, settings, deps),
         {:ok, _result} <-
           deps.accounts_verify.(request.provider_kind, request.account_id, request.verify_opts, settings) do
      log_preflight(deps, "Managed credential preflight passed for #{credential_label(request)}.")
      :ok
    else
      {:error, reason} ->
        {:error, "#{credential_label(request)}: #{verify_failure_message(reason, request)}"}
    end
  end

  defp maybe_login_preflight(%{login_opts: nil} = request, _settings, deps) do
    log_preflight(
      deps,
      "No #{request.token_env} provided; verifying existing managed credential for #{credential_label(request)}."
    )

    :ok
  end

  defp maybe_login_preflight(request, settings, deps) do
    case deps.accounts_login.(request.provider_kind, request.account_id, request.login_opts, settings) do
      {:ok, _account} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_failure_message(reason, %{login_opts: nil} = request) do
    "#{format_reason(reason)}; #{request.credential_hint}"
  end

  defp verify_failure_message(reason, _request), do: format_reason(reason)

  defp credential_label(%{provider_kind: provider_kind, account_id: account_id}) do
    "#{provider_kind}/#{account_id}"
  end

  defp log_preflight(deps, message) do
    deps
    |> Map.get(:log, fn _message -> :ok end)
    |> then(& &1.(message))
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
