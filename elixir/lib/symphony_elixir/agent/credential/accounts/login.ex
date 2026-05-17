defmodule SymphonyElixir.Agent.Credential.Accounts.Login do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.Accounts.{Command, Options, ProviderCallbacks, Secret}
  alias SymphonyElixir.Agent.Credential.Store
  alias SymphonyElixir.AgentProvider.ClaudeCode.CredentialEnv, as: ClaudeCredentialEnv
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.AgentProvider.OpenCode.CredentialEnv, as: OpenCodeCredentialEnv

  @claude_code_kind Kinds.claude_code()
  @claude_oauth_token_credential_kind ClaudeCredentialEnv.oauth_token_credential_kind()
  @opencode_kind Kinds.opencode()
  @opencode_env_token_credential_kind OpenCodeCredentialEnv.env_token_credential_kind()

  @spec login(String.t(), String.t(), keyword(), keyword() | map() | nil) :: {:ok, Store.account()} | {:error, term()}
  def login(provider_kind, id, opts, store_opts) do
    case ProviderCallbacks.account_login(provider_kind, id, opts, store_opts) do
      :unsupported ->
        case provider_kind do
          @claude_code_kind -> login_claude_code(id, opts, store_opts)
          @opencode_kind -> login_opencode(id, opts, store_opts)
          provider -> {:error, {:unsupported_account_login_provider, provider}}
        end

      result ->
        result
    end
  end

  defp login_claude_code(id, opts, store_opts) do
    attrs = Options.attrs(opts, credential_kind: @claude_oauth_token_credential_kind)

    with {:ok, account} <- Store.create_or_update(@claude_code_kind, id, attrs, store_opts),
         {:ok, oauth_token} <- claude_oauth_token(account, opts),
         :ok <- Secret.write(account.secret_file, oauth_token),
         {:ok, account} <- Store.create_or_update(@claude_code_kind, id, attrs, store_opts) do
      {:ok, account}
    end
  end

  defp login_opencode(id, opts, store_opts) do
    with {:ok, env_name} <- Options.opencode_env_name(opts),
         {:ok, token} <- Options.required_token(opts, :missing_opencode_token) do
      attrs = Options.attrs(opts, credential_kind: @opencode_env_token_credential_kind, env_name: env_name)

      with {:ok, account} <- Store.create_or_update(@opencode_kind, id, attrs, store_opts),
           :ok <- Secret.write(account.secret_file, token),
           {:ok, account} <- Store.create_or_update(@opencode_kind, id, attrs, store_opts) do
        {:ok, account}
      end
    end
  end

  defp claude_oauth_token(account, opts) do
    case Keyword.get(opts, :token) do
      token when is_binary(token) ->
        token = String.trim(token)

        if token == "" do
          {:error, :missing_claude_oauth_token}
        else
          {:ok, token}
        end

      _token ->
        command = Keyword.get(opts, :command) || "claude"

        command
        |> Command.run(
          ["setup-token"],
          [],
          opts
          |> Keyword.put(:stream, true)
          |> Keyword.put_new(:tty_capture, true)
          |> Keyword.put(:transcript_path, Path.join(account.account_dir, "claude_setup_token.transcript"))
        )
        |> case do
          {:ok, output} -> extract_claude_oauth_token(output)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp extract_claude_oauth_token(output) when is_binary(output) do
    case Regex.scan(~r/(sk-ant-oat[A-Za-z0-9._:-]+|oauth[A-Za-z0-9._:-]+|claude[A-Za-z0-9._:-]+)/, output) do
      [] -> {:error, :missing_claude_oauth_token}
      matches -> {:ok, matches |> List.last() |> List.last()}
    end
  end
end
