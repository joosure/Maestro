defmodule SymphonyElixir.AgentProvider.Codex.Credential do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.{Lease, Material}
  alias SymphonyElixir.Agent.Runtime.Target
  alias SymphonyElixir.AgentProvider.Codex.CredentialEnv
  alias SymphonyElixir.AgentProvider.Kinds

  @provider_kind Kinds.codex()
  @api_key_credential_kind CredentialEnv.api_key_credential_kind()
  @secret_mode 0o600
  @dir_mode 0o700
  @file_store_config "cli_auth_credentials_store = \"file\"\n"
  @local_root "symphony-codex-credentials"
  @remote_root "/tmp/symphony-codex-credentials"

  @spec materialize_api_key(map(), Lease.t(), keyword()) :: {:ok, Material.t()} | {:error, term()}
  def materialize_api_key(account, %Lease{} = lease, opts \\ []) when is_map(account) and is_list(opts) do
    with {:ok, api_key} <- read_api_key(account),
         {:ok, codex_home} <- codex_home(lease, opts) do
      if remote_materialization?(opts) do
        {:ok, remote_material(api_key, codex_home, lease)}
      else
        local_material(api_key, codex_home, lease)
      end
    end
  end

  @spec remote_auth_commands(Material.t() | term()) :: {[String.t()], [String.t()]}
  def remote_auth_commands(%Material{auth_metadata: %{@provider_kind => %{"credential_kind" => @api_key_credential_kind} = metadata}}) do
    with api_key when is_binary(api_key) and api_key != "" <- Map.get(metadata, "api_key"),
         codex_home when is_binary(codex_home) and codex_home != "" <- Map.get(metadata, "codex_home") do
      auth_json = Jason.encode!(CredentialEnv.auth_payload(api_key))

      setup_commands = [
        "rm -rf #{shell_escape(codex_home)}",
        "mkdir -p #{shell_escape(codex_home)}",
        "chmod 700 #{shell_escape(codex_home)}",
        "printf %s #{shell_escape(@file_store_config)} > #{shell_escape(Path.join(codex_home, "config.toml"))}",
        "printf %s #{shell_escape(auth_json)} > #{shell_escape(Path.join(codex_home, "auth.json"))}",
        "chmod 600 #{shell_escape(Path.join(codex_home, "config.toml"))} #{shell_escape(Path.join(codex_home, "auth.json"))}"
      ]

      {setup_commands, ["rm -rf #{shell_escape(codex_home)}"]}
    else
      _missing -> {[], []}
    end
  end

  def remote_auth_commands(_material), do: {[], []}

  defp local_material(api_key, codex_home, %Lease{} = lease) do
    case write_codex_home(codex_home, api_key) do
      :ok ->
        {:ok,
         Material.new(%{
           env: CredentialEnv.materialized_env(codex_home),
           auth_metadata: %{
             @provider_kind => %{
               "credential_kind" => @api_key_credential_kind,
               "codex_home" => codex_home
             }
           },
           summary: material_summary(codex_home, lease, "file"),
           cleanup: [{:rm_rf, codex_home}]
         })}

      {:error, reason} ->
        _ = File.rm_rf(codex_home)
        {:error, reason}
    end
  end

  defp remote_material(api_key, codex_home, %Lease{} = lease) do
    Material.new(%{
      env: CredentialEnv.materialized_env(codex_home),
      auth_metadata: %{
        @provider_kind => %{
          "credential_kind" => @api_key_credential_kind,
          "codex_home" => codex_home,
          "api_key" => api_key
        }
      },
      summary: material_summary(codex_home, lease, "remote_file")
    })
  end

  defp material_summary(codex_home, %Lease{} = lease, storage) do
    %{
      credential_kind: @api_key_credential_kind,
      auth_shape: CredentialEnv.auth_shape(),
      credential_store: storage,
      codex_home_summary: path_summary(codex_home),
      account_id_summary: lease.account_id
    }
  end

  defp write_codex_home(codex_home, api_key) do
    config_path = Path.join(codex_home, "config.toml")
    auth_path = Path.join(codex_home, "auth.json")

    with :ok <- mkdir_private(codex_home),
         :ok <- write_private_file(config_path, @file_store_config),
         :ok <- write_private_file(auth_path, Jason.encode!(CredentialEnv.auth_payload(api_key))) do
      :ok
    end
  end

  defp read_api_key(%{secret_file: path}) when is_binary(path) do
    case File.read(path) do
      {:ok, contents} ->
        case String.trim(contents) do
          "" -> {:error, :missing_codex_api_key}
          api_key -> {:ok, api_key}
        end

      {:error, reason} ->
        {:error, {:codex_api_key_read, reason}}
    end
  end

  defp read_api_key(_account), do: {:error, :missing_codex_api_key}

  defp codex_home(%Lease{} = lease, opts) do
    if remote_materialization?(opts) do
      {:ok, Path.join(remote_root(opts), material_dir_name(lease))}
    else
      root = local_root(opts)
      path = Path.join(root, material_dir_name(lease))

      {:ok, path}
    end
  end

  defp local_root(opts) do
    opts
    |> Keyword.get(:codex_credential_material_root)
    |> normalize_optional_string()
    |> case do
      nil -> Path.join(System.tmp_dir!(), @local_root)
      root -> Path.expand(root)
    end
  end

  defp remote_root(opts) do
    opts
    |> Keyword.get(:codex_remote_credential_root)
    |> normalize_optional_string()
    |> case do
      nil -> @remote_root
      root -> root
    end
  end

  defp material_dir_name(%Lease{} = lease) do
    base =
      [lease.provider_kind, lease.account_id, lease.id, System.unique_integer([:positive])]
      |> Enum.map(&normalize_optional_string/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("-")

    "codex-" <> safe_path_component(base)
  end

  defp remote_materialization?(opts) when is_list(opts) do
    case runtime_placement(opts) do
      "ssh" -> true
      "worker_daemon" -> true
      _placement -> false
    end
  end

  defp runtime_placement(opts) do
    context = Keyword.get(opts, :provider_runtime_context) || %{}

    cond do
      match?(%Target{}, Map.get(context, :agent_runtime_target) || Map.get(context, "agent_runtime_target")) ->
        target = Map.get(context, :agent_runtime_target) || Map.get(context, "agent_runtime_target")
        Atom.to_string(target.placement)

      is_binary(Map.get(context, :worker_placement)) ->
        Map.get(context, :worker_placement)

      is_binary(Map.get(context, "worker_placement")) ->
        Map.get(context, "worker_placement")

      is_binary(Keyword.get(opts, :worker_host)) ->
        "ssh"

      true ->
        "local"
    end
  end

  defp mkdir_private(path) do
    with :ok <- File.mkdir_p(path), do: File.chmod(path, @dir_mode)
  end

  defp write_private_file(path, contents) do
    with :ok <- File.write(path, contents), do: File.chmod(path, @secret_mode)
  end

  defp safe_path_component(value) when is_binary(value) do
    value
    |> String.replace(~r/[^A-Za-z0-9_.-]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> Integer.to_string(System.unique_integer([:positive]))
      safe -> safe
    end
  end

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp path_summary(path) when is_binary(path), do: Path.basename(path)

  defp shell_escape(value) do
    "'#{String.replace(to_string(value), "'", "'\"'\"'")}'"
  end
end
