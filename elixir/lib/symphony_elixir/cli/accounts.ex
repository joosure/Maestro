defmodule SymphonyElixir.CLI.Accounts do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.Accounts, as: AgentAccounts
  alias SymphonyElixir.CLI.Accounts.{Parser, Renderer, TokenSource}

  @type deps :: %{
          required(:file_regular?) => (String.t() -> boolean()),
          required(:set_workflow_file_path) => (String.t() -> :ok | {:error, term()}),
          optional(:accounts_login) => (String.t(), String.t(), keyword() -> {:ok, map()} | {:error, term()}),
          optional(:accounts_import) => (String.t(), String.t(), keyword() -> {:ok, map()} | {:error, term()}),
          optional(:accounts_list) => (String.t() | nil -> {:ok, [map()]} | {:error, term()}),
          optional(:accounts_verify) => (String.t(), String.t(), keyword() -> {:ok, map()} | {:error, term()}),
          optional(:accounts_pause) => (String.t(), String.t(), keyword() -> {:ok, map()} | {:error, term()}),
          optional(:accounts_resume) => (String.t(), String.t() -> {:ok, map()} | {:error, term()}),
          optional(:accounts_remove) => (String.t(), String.t() -> :ok | {:error, term()}),
          optional(:accounts_enable) => (String.t(), String.t() -> {:ok, map()} | {:error, term()}),
          optional(:accounts_disable) => (String.t(), String.t() -> {:ok, map()} | {:error, term()}),
          optional(:accounts_list_leases) => (String.t() | nil, String.t() | nil -> {:ok, [map()]} | {:error, term()}),
          optional(:accounts_release_lease) => (String.t(), String.t(), String.t() -> {:ok, map()} | {:error, term()})
        }

  @doc false
  @spec runtime_deps() :: map()
  def runtime_deps do
    %{
      accounts_login: &AgentAccounts.login/3,
      accounts_import: &AgentAccounts.import_account/3,
      accounts_list: &AgentAccounts.list/1,
      accounts_verify: &AgentAccounts.verify/3,
      accounts_pause: &AgentAccounts.pause/3,
      accounts_resume: &AgentAccounts.resume/2,
      accounts_remove: &AgentAccounts.remove/2,
      accounts_enable: &AgentAccounts.enable/2,
      accounts_disable: &AgentAccounts.disable/2,
      accounts_list_leases: &AgentAccounts.list_leases/2,
      accounts_release_lease: &AgentAccounts.release_lease/3
    }
  end

  @spec evaluate([String.t()], deps(), String.t()) :: :ok | {:error, String.t()}
  def evaluate(args, deps, usage)

  def evaluate(["login", provider_kind, id | rest], deps, usage) do
    with {:ok, opts, workflow_path} <-
           Parser.parse_options(rest, usage,
             email: :string,
             command: :string,
             token: :string,
             token_stdin: :boolean,
             token_file: :string,
             token_env: :string,
             env_name: :string,
             internet_environment: :string
           ),
         {:ok, opts} <- TokenSource.resolve_login_opts(opts),
         :ok <- maybe_set_workflow_path(workflow_path, deps),
         {:ok, account} <- account_dep(deps, :accounts_login).(provider_kind, id, opts) do
      Renderer.stored(account)
      :ok
    else
      {:error, %OptionParser.ParseError{} = error} -> {:error, error.message}
      {:error, reason} -> {:error, "Failed to login account: #{Renderer.format_error(reason)}"}
    end
  end

  def evaluate(["import", provider_kind, id | rest], deps, usage) do
    with {:ok, opts, workflow_path} <-
           Parser.parse_options(rest, usage,
             email: :string,
             from: :string,
             global_config_file: :string
           ),
         :ok <- maybe_set_workflow_path(workflow_path, deps),
         {:ok, account} <- account_dep(deps, :accounts_import).(provider_kind, id, opts) do
      Renderer.imported(account)
      :ok
    else
      {:error, %OptionParser.ParseError{} = error} -> {:error, error.message}
      {:error, reason} -> {:error, "Failed to import account: #{Renderer.format_error(reason)}"}
    end
  end

  def evaluate(["list" | rest], deps, usage) do
    with {:ok, provider_kind, workflow_path} <- Parser.parse_list_options(rest, usage),
         :ok <- maybe_set_workflow_path(workflow_path, deps),
         {:ok, accounts} <- account_dep(deps, :accounts_list).(provider_kind) do
      Renderer.listed(accounts)
      :ok
    else
      {:error, %OptionParser.ParseError{} = error} -> {:error, error.message}
      {:error, reason} -> {:error, "Failed to list accounts: #{Renderer.format_error(reason)}"}
    end
  end

  def evaluate(["verify", provider_kind, id | rest], deps, usage) do
    with {:ok, opts, workflow_path} <- Parser.parse_options(rest, usage, command: :string),
         :ok <- maybe_set_workflow_path(workflow_path, deps),
         {:ok, result} <- account_dep(deps, :accounts_verify).(provider_kind, id, opts) do
      Renderer.verified(result, provider_kind, id)
      :ok
    else
      {:error, %OptionParser.ParseError{} = error} -> {:error, error.message}
      {:error, reason} -> {:error, "Failed to verify account: #{Renderer.format_error(reason)}"}
    end
  end

  def evaluate(["pause", provider_kind, id | rest], deps, usage) do
    with {:ok, opts, workflow_path} <- Parser.parse_options(rest, usage, until: :string, reason: :string),
         :ok <- maybe_set_workflow_path(workflow_path, deps),
         {:ok, account} <- account_dep(deps, :accounts_pause).(provider_kind, id, opts) do
      Renderer.paused(account)
      :ok
    else
      {:error, %OptionParser.ParseError{} = error} -> {:error, error.message}
      {:error, reason} -> {:error, "Failed to pause account: #{Renderer.format_error(reason)}"}
    end
  end

  def evaluate(["resume", provider_kind, id | rest], deps, usage) do
    with {:ok, _opts, workflow_path} <- Parser.parse_options(rest, usage, []),
         :ok <- maybe_set_workflow_path(workflow_path, deps),
         {:ok, account} <- account_dep(deps, :accounts_resume).(provider_kind, id) do
      Renderer.resumed(account)
      :ok
    else
      {:error, %OptionParser.ParseError{} = error} -> {:error, error.message}
      {:error, reason} -> {:error, "Failed to resume account: #{Renderer.format_error(reason)}"}
    end
  end

  def evaluate(["remove", provider_kind, id | rest], deps, usage) do
    with {:ok, _opts, workflow_path} <- Parser.parse_options(rest, usage, []),
         :ok <- maybe_set_workflow_path(workflow_path, deps) do
      case account_dep(deps, :accounts_remove).(provider_kind, id) do
        :ok ->
          Renderer.removed(provider_kind, id)
          :ok

        {:error, reason} ->
          {:error, "Failed to remove account: #{Renderer.format_error(reason)}"}
      end
    else
      {:error, %OptionParser.ParseError{} = error} -> {:error, error.message}
      {:error, reason} -> {:error, "Failed to remove account: #{Renderer.format_error(reason)}"}
    end
  end

  def evaluate(["enable", provider_kind, id | rest], deps, usage) do
    with {:ok, _opts, workflow_path} <- Parser.parse_options(rest, usage, []),
         :ok <- maybe_set_workflow_path(workflow_path, deps),
         {:ok, account} <- account_dep(deps, :accounts_enable).(provider_kind, id) do
      Renderer.enabled(account)
      :ok
    else
      {:error, %OptionParser.ParseError{} = error} -> {:error, error.message}
      {:error, reason} -> {:error, "Failed to enable account: #{Renderer.format_error(reason)}"}
    end
  end

  def evaluate(["disable", provider_kind, id | rest], deps, usage) do
    with {:ok, _opts, workflow_path} <- Parser.parse_options(rest, usage, []),
         :ok <- maybe_set_workflow_path(workflow_path, deps),
         {:ok, account} <- account_dep(deps, :accounts_disable).(provider_kind, id) do
      Renderer.disabled(account)
      :ok
    else
      {:error, %OptionParser.ParseError{} = error} -> {:error, error.message}
      {:error, reason} -> {:error, "Failed to disable account: #{Renderer.format_error(reason)}"}
    end
  end

  def evaluate(["leases", "list" | rest], deps, usage) do
    with {:ok, provider_kind, id, workflow_path} <- Parser.parse_lease_list_options(rest, usage),
         :ok <- maybe_set_workflow_path(workflow_path, deps),
         {:ok, leases} <- account_dep(deps, :accounts_list_leases).(provider_kind, id) do
      Renderer.leases_listed(leases)
      :ok
    else
      {:error, %OptionParser.ParseError{} = error} -> {:error, error.message}
      {:error, reason} -> {:error, "Failed to list credential leases: #{Renderer.format_error(reason)}"}
    end
  end

  def evaluate(["leases", "release" | rest], deps, usage) do
    with {:ok, provider_kind, id, lease_id, workflow_path} <- Parser.parse_lease_release_options(rest, usage),
         :ok <- maybe_set_workflow_path(workflow_path, deps),
         {:ok, lease} <- account_dep(deps, :accounts_release_lease).(provider_kind, id, lease_id) do
      Renderer.lease_released(lease)
      :ok
    else
      {:error, %OptionParser.ParseError{} = error} -> {:error, error.message}
      {:error, reason} -> {:error, "Failed to release credential lease: #{Renderer.format_error(reason)}"}
    end
  end

  def evaluate(_args, _deps, usage), do: {:error, usage}

  defp maybe_set_workflow_path(nil, deps) do
    default_path = Path.expand("WORKFLOW.md")

    if deps.file_regular?.(default_path) do
      deps.set_workflow_file_path.(default_path)
    else
      :ok
    end
  end

  defp maybe_set_workflow_path(workflow_path, deps) when is_binary(workflow_path) do
    expanded_path = Path.expand(workflow_path)

    if deps.file_regular?.(expanded_path) do
      deps.set_workflow_file_path.(expanded_path)
    else
      {:error, "Workflow file not found: #{expanded_path}"}
    end
  end

  defp account_dep(deps, key), do: Map.get(deps, key, Map.fetch!(runtime_deps(), key))
end
