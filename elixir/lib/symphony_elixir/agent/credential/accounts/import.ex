defmodule SymphonyElixir.Agent.Credential.Accounts.Import do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.Accounts.{Options, Secret}
  alias SymphonyElixir.Agent.Credential.Store

  @claude_import_files [
    ".claude.json",
    ".config.json",
    "settings.json",
    "settings.local.json",
    "policy-limits.json",
    "mcp-needs-auth-cache.json"
  ]

  @spec import_account(String.t(), String.t(), keyword(), keyword() | map() | nil) ::
          {:ok, Store.account()} | {:error, term()}
  def import_account("claude_code", id, opts, store_opts), do: import_claude_code_account(id, opts, store_opts)
  def import_account(provider, _id, _opts, _store_opts), do: {:error, {:unsupported_account_import_provider, provider}}

  defp import_claude_code_account(id, opts, store_opts) do
    attrs = Options.attrs(opts, credential_kind: "claude_config")

    with {:ok, account} <- Store.create_or_update("claude_code", id, attrs, store_opts),
         :ok <- import_claude_config_files(account, opts),
         {:ok, account} <- Store.get("claude_code", id, store_opts) do
      {:ok, account}
    end
  end

  defp import_claude_config_files(account, opts) do
    source_dir = claude_import_source_dir(opts)
    destination_dir = account.auth_dir

    with :ok <- Secret.mkdir_private(destination_dir) do
      copied_files =
        []
        |> copy_optional_claude_global_config(source_dir, destination_dir, opts)
        |> copy_optional_claude_config_dir_files(source_dir, destination_dir)

      case copied_files do
        [] -> {:error, {:missing_claude_config, source_dir}}
        _files -> :ok
      end
    end
  end

  defp claude_import_source_dir(opts) do
    opts
    |> Keyword.get(:from)
    |> case do
      source when is_binary(source) and source != "" ->
        Path.expand(source)

      _source ->
        case System.get_env("CLAUDE_CONFIG_DIR") do
          source when is_binary(source) and source != "" -> Path.expand(source)
          _env -> Path.expand("~/.claude")
        end
    end
  end

  defp copy_optional_claude_global_config(copied_files, source_dir, destination_dir, opts) do
    source_dir
    |> claude_global_config_candidates(opts)
    |> Enum.reduce(copied_files, fn source_path, copied ->
      Secret.copy_optional_file(source_path, Path.join(destination_dir, ".claude.json"), copied)
    end)
  end

  defp claude_global_config_candidates(source_dir, opts) do
    configured =
      case Keyword.get(opts, :global_config_file) do
        path when is_binary(path) and path != "" -> [Path.expand(path)]
        _path -> []
      end

    source_local = Path.join(source_dir, ".claude.json")
    default_global = if Path.expand(source_dir) == Path.expand("~/.claude"), do: [Path.expand("~/.claude.json")], else: []

    (default_global ++ [source_local] ++ configured)
    |> Enum.uniq()
  end

  defp copy_optional_claude_config_dir_files(copied_files, source_dir, destination_dir) do
    Enum.reduce(@claude_import_files, copied_files, fn file_name, copied ->
      Secret.copy_optional_file(Path.join(source_dir, file_name), Path.join(destination_dir, file_name), copied)
    end)
  end
end
