defmodule SymphonyElixir.AgentProvider.ReleaseCredentialPreflight do
  @moduledoc """
  Contract and helpers for provider-owned release credential preflight plans.

  A provider that can initialize managed credentials during release/container
  startup should expose its plan module from the adapter via
  `release_credential_preflight_plan/0`.

  Provider plan modules own provider-specific token discovery, login options,
  and verification options. The release layer only discovers a plan module and
  executes this contract, which keeps adding a new provider local to the
  provider directory.
  """

  alias SymphonyElixir.Platform.Env

  @default_auth_probe_prompt "Reply with exactly OK."
  @verify_mode_env "SYMPHONY_AGENT_CREDENTIAL_PREFLIGHT_VERIFY_MODE"
  @verify_prompt_env "SYMPHONY_AGENT_CREDENTIAL_PREFLIGHT_VERIFY_PROMPT"

  defmodule LoginPlan do
    @moduledoc """
    Provider-owned managed credential login plan used by release preflight.

    `login_opts` is `nil` when startup should verify an already-persisted
    credential without creating or rotating it.
    """

    defstruct credential_hint: nil, login_opts: nil, token_env: nil

    @type t :: %__MODULE__{
            credential_hint: String.t(),
            login_opts: keyword() | nil,
            token_env: String.t()
          }

    @spec new(map() | keyword()) :: {:ok, t()} | {:error, String.t()}
    def new(attrs) when is_list(attrs) do
      if Keyword.keyword?(attrs) do
        attrs |> Map.new() |> new()
      else
        {:error, "login plan must be a map or keyword list, got #{inspect(attrs)}"}
      end
    end

    def new(attrs) when is_map(attrs) do
      plan = %__MODULE__{
        credential_hint: Map.get(attrs, :credential_hint) || Map.get(attrs, "credential_hint"),
        login_opts: Map.get(attrs, :login_opts, Map.get(attrs, "login_opts")),
        token_env: Map.get(attrs, :token_env) || Map.get(attrs, "token_env")
      }

      with {:ok, credential_hint} <- validate_required_string(plan.credential_hint, :credential_hint),
           {:ok, token_env} <- validate_required_string(plan.token_env, :token_env),
           :ok <- validate_login_opts(plan.login_opts) do
        {:ok, %{plan | credential_hint: credential_hint, token_env: token_env}}
      end
    end

    def new(attrs), do: {:error, "login plan must be a map or keyword list, got #{inspect(attrs)}"}

    defp validate_required_string(value, field) when is_binary(value) do
      value = String.trim(value)

      if value == "" do
        {:error, "login plan #{field} must be a non-empty string"}
      else
        {:ok, value}
      end
    end

    defp validate_required_string(_value, field), do: {:error, "login plan #{field} must be a non-empty string"}

    defp validate_login_opts(nil), do: :ok

    defp validate_login_opts(opts) when is_list(opts) do
      if Keyword.keyword?(opts) do
        :ok
      else
        {:error, "login plan login_opts must be a keyword list or nil, got #{inspect(opts)}"}
      end
    end

    defp validate_login_opts(opts), do: {:error, "login plan login_opts must be a keyword list or nil, got #{inspect(opts)}"}
  end

  @doc "Returns the provider kind this preflight plan is allowed to serve."
  @callback provider_kind() :: String.t()

  @doc """
  Builds the provider-owned credential login plan for an account.

  Return `login_opts: nil` when the provider should only verify an existing
  persisted credential. Return login options when the release preflight should
  create or rotate the managed credential before verification.
  """
  @callback login_plan(String.t(), map()) :: {:ok, LoginPlan.t()} | {:error, String.t()}

  @doc """
  Builds provider-owned options for `accounts verify`.

  Command-only providers can return a command override. Providers that support
  real auth probes should return `auth_probe` options from this callback.
  """
  @callback verify_opts(map(), map()) :: {:ok, keyword()} | {:error, String.t()}

  @spec verify_mode_env() :: String.t()
  def verify_mode_env, do: @verify_mode_env

  @spec verify_prompt_env() :: String.t()
  def verify_prompt_env, do: @verify_prompt_env

  @spec valid_plan_module?(module(), String.t()) :: boolean()
  def valid_plan_module?(plan_module, provider_kind) when is_atom(plan_module) and is_binary(provider_kind) do
    validate_plan_module(plan_module, provider_kind) == :ok
  end

  @spec validate_plan_module(module(), String.t()) :: :ok | {:error, String.t()}
  def validate_plan_module(plan_module, provider_kind) when is_atom(plan_module) and is_binary(provider_kind) do
    with :ok <- ensure_plan_module_loaded(plan_module),
         :ok <- ensure_required_callbacks(plan_module),
         :ok <- validate_provider_kind(plan_module, provider_kind) do
      :ok
    end
  end

  def validate_plan_module(plan_module, _provider_kind) do
    {:error, "expected a plan module atom, got #{inspect(plan_module)}"}
  end

  @spec login_plan(module(), String.t(), map()) :: {:ok, LoginPlan.t()} | {:error, String.t()}
  def login_plan(plan_module, account_id, env_map) do
    case call_callback(plan_module, :login_plan, [account_id, env_map]) do
      {:ok, {:ok, login_plan}} ->
        normalize_login_plan(login_plan, plan_module)

      {:ok, {:error, reason}} when is_binary(reason) ->
        {:error, reason}

      {:ok, {:error, reason}} ->
        {:error, "login plan from #{inspect(plan_module)} failed: #{inspect(reason)}"}

      {:ok, other} ->
        {:error, "login plan from #{inspect(plan_module)} returned #{inspect(other)}, expected {:ok, plan} or {:error, reason}"}

      {:error, reason} ->
        {:error, "login_plan/2 from #{inspect(plan_module)} failed: #{reason}"}
    end
  end

  @spec verify_opts(module(), map(), map()) :: {:ok, keyword()} | {:error, String.t()}
  def verify_opts(plan_module, env_map, settings) do
    case call_callback(plan_module, :verify_opts, [env_map, settings]) do
      {:ok, {:ok, opts}} ->
        normalize_verify_opts(opts, plan_module)

      {:ok, {:error, reason}} when is_binary(reason) ->
        {:error, reason}

      {:ok, {:error, reason}} ->
        {:error, "verify opts from #{inspect(plan_module)} failed: #{inspect(reason)}"}

      {:ok, other} ->
        {:error, "verify opts from #{inspect(plan_module)} returned #{inspect(other)}, expected {:ok, keyword} or {:error, reason}"}

      {:error, reason} ->
        {:error, "verify_opts/2 from #{inspect(plan_module)} failed: #{reason}"}
    end
  end

  @spec env_token_login_plan(map(), keyword()) :: {:ok, LoginPlan.t()} | {:error, String.t()}
  def env_token_login_plan(env_map, opts) when is_map(env_map) and is_list(opts) do
    token_env_config = Keyword.fetch!(opts, :token_env_config)
    default_token_env = Keyword.fetch!(opts, :default_token_env)
    login_option_specs = Keyword.fetch!(opts, :login_option_specs)
    token_context = Keyword.get(opts, :token_context, %{})

    with {:ok, token_env} <- Env.env_name(env_map, token_env_config, default_token_env) do
      credential_hint = Map.get(token_context, :credential_hint, missing_token_hint(token_env))

      case Env.value(env_map, token_env) do
        nil ->
          LoginPlan.new(%{credential_hint: credential_hint, login_opts: nil, token_env: token_env})

        token ->
          token_context = Map.put(token_context, :token, token)

          LoginPlan.new(%{
            credential_hint: credential_hint,
            login_opts: login_opts(login_option_specs, token_context, env_map),
            token_env: token_env
          })
      end
    end
  end

  @spec normalize_login_plan(term(), module()) :: {:ok, LoginPlan.t()} | {:error, String.t()}
  def normalize_login_plan(plan, plan_module) do
    case LoginPlan.new(plan) do
      {:ok, plan} -> {:ok, plan}
      {:error, reason} -> {:error, "invalid login plan from #{inspect(plan_module)}: #{reason}"}
    end
  end

  @spec normalize_verify_opts(term(), module()) :: {:ok, keyword()} | {:error, String.t()}
  def normalize_verify_opts(opts, plan_module) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, opts}
    else
      {:error, "invalid verify opts from #{inspect(plan_module)}: expected keyword list, got #{inspect(opts)}"}
    end
  end

  def normalize_verify_opts(opts, plan_module) do
    {:error, "invalid verify opts from #{inspect(plan_module)}: expected keyword list, got #{inspect(opts)}"}
  end

  @spec auth_probe_verify_opts(map(), map(), String.t()) :: {:ok, keyword()} | {:error, String.t()}
  def auth_probe_verify_opts(env_map, settings, verify_command_env) do
    with {:ok, verify_mode} <- verify_mode(env_map) do
      opts =
        env_map
        |> command_opt(verify_command_env)
        |> Keyword.merge(verify_probe_opts(verify_mode, env_map, settings))

      {:ok, opts}
    end
  end

  @spec command_verify_opts(map(), String.t()) :: {:ok, keyword()} | {:error, String.t()}
  def command_verify_opts(env_map, verify_command_env) do
    with {:ok, _verify_mode} <- verify_mode(env_map) do
      {:ok, command_opt(env_map, verify_command_env)}
    end
  end

  defp login_opts(login_option_specs, token_context, env_map) do
    Enum.map(login_option_specs, fn {key, value_spec} ->
      {key, login_option_value(value_spec, token_context, env_map)}
    end)
  end

  defp login_option_value(:token, token_context, _env_map), do: Map.fetch!(token_context, :token)
  defp login_option_value({:value, key}, token_context, _env_map), do: Map.fetch!(token_context, key)
  defp login_option_value({:env, name, default}, _token_context, env_map), do: Env.value(env_map, name, default)

  defp verify_mode(env_map) do
    value =
      env_map
      |> Env.value(@verify_mode_env, "auth")
      |> String.downcase()

    cond do
      value in ["auth", "auth_probe", "strict"] ->
        {:ok, :auth_probe}

      value in ["command", "version", "cli"] ->
        {:ok, :command}

      true ->
        {:error, "invalid #{@verify_mode_env}=#{inspect(value)}; use auth or command"}
    end
  end

  defp verify_probe_opts(:command, _env_map, _settings), do: []

  defp verify_probe_opts(:auth_probe, env_map, settings) do
    opts = [
      auth_probe: true,
      prompt: Env.value(env_map, @verify_prompt_env, @default_auth_probe_prompt)
    ]

    case provider_model(settings) do
      nil -> opts
      model -> Keyword.put(opts, :model, model)
    end
  end

  defp provider_model(settings) do
    settings
    |> Env.nested([:agent_provider, :options, :model])
    |> Env.normalize_string()
  end

  defp command_opt(env_map, name) do
    case Env.value(env_map, name) do
      nil -> []
      command -> [command: command]
    end
  end

  defp missing_token_hint(token_env) do
    "if this credential is not initialized or needs rotation, set #{token_env} to create or update it automatically"
  end

  defp ensure_plan_module_loaded(plan_module) do
    if Code.ensure_loaded?(plan_module) do
      :ok
    else
      {:error, "plan module #{inspect(plan_module)} is not loaded"}
    end
  end

  defp ensure_required_callbacks(plan_module) do
    case missing_callbacks(plan_module) do
      [] -> :ok
      callbacks -> {:error, "plan module #{inspect(plan_module)} is missing callbacks: #{format_callbacks(callbacks)}"}
    end
  end

  defp missing_callbacks(plan_module) do
    [
      {:provider_kind, 0},
      {:login_plan, 2},
      {:verify_opts, 2}
    ]
    |> Enum.reject(fn {function, arity} -> function_exported?(plan_module, function, arity) end)
  end

  defp format_callbacks(callbacks) do
    Enum.map_join(callbacks, ", ", fn {function, arity} -> "#{function}/#{arity}" end)
  end

  defp validate_provider_kind(plan_module, expected_provider_kind) do
    case call_provider_kind(plan_module) do
      {:ok, ^expected_provider_kind} ->
        :ok

      {:ok, actual_provider_kind} ->
        {:error, "plan module #{inspect(plan_module)} declares provider_kind #{inspect(actual_provider_kind)}, expected #{inspect(expected_provider_kind)}"}

      {:error, reason} ->
        {:error, "plan module #{inspect(plan_module)} provider_kind/0 failed: #{reason}"}
    end
  end

  defp call_provider_kind(plan_module) do
    {:ok, plan_module.provider_kind()}
  rescue
    exception ->
      {:error, Exception.message(exception)}
  catch
    kind, reason ->
      {:error, "#{kind} #{inspect(reason)}"}
  end

  defp call_callback(plan_module, function, args) do
    {:ok, apply(plan_module, function, args)}
  rescue
    exception ->
      {:error, "raised #{Exception.message(exception)}"}
  catch
    kind, reason ->
      {:error, "threw #{kind} #{inspect(reason)}"}
  end
end
