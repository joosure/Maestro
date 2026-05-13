defmodule SymphonyElixir.AgentProvider.Codex.CredentialTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias SymphonyElixir.Agent.Credential
  alias SymphonyElixir.Agent.Credential.{Accounts, Lease, Store}
  alias SymphonyElixir.AgentProvider.Codex
  alias SymphonyElixir.AgentProvider.Config, as: ProviderConfig

  test "materializes codex_api_key as file-backed CODEX_HOME and cleans it up" do
    store_root = temp_root!("store")
    material_root = temp_root!("material")
    opts = store_opts(store_root)

    {:ok, account} = Accounts.login("codex", "openai", [token: "sk-codex-material"], opts)
    {:ok, lease} = Store.acquire("codex", Store.credential_ref(account), Keyword.put(opts, :run_id, "run-codex-material"))

    config = ProviderConfig.new(%{kind: "codex", options: %{"credential_ref" => Store.credential_ref(account)}})

    assert {:ok, material} =
             Codex.Adapter.materialize_credential(
               config,
               lease,
               Keyword.put(opts, :codex_credential_material_root, material_root)
             )

    codex_home = material.env["CODEX_HOME"]
    assert is_binary(codex_home)
    refute Map.has_key?(material.env, "OPENAI_API_KEY")
    assert File.exists?(codex_home)
    assert File.read!(Path.join(codex_home, "config.toml")) == "cli_auth_credentials_store = \"file\"\n"

    auth = codex_home |> Path.join("auth.json") |> File.read!() |> Jason.decode!()
    assert auth == %{"auth_mode" => "apikey", "OPENAI_API_KEY" => "sk-codex-material"}

    assert_mode(codex_home, 0o700)
    assert_mode(Path.join(codex_home, "auth.json"), 0o600)

    assert :ok =
             Credential.release_provider_start(
               config,
               %{agent_credential_lease: lease, agent_credential_material: material},
               opts
             )

    refute File.exists?(codex_home)
  end

  test "remote materialization returns CODEX_HOME and setup commands without OPENAI_API_KEY env injection" do
    store_root = temp_root!("remote-store")
    opts = store_opts(store_root)

    {:ok, account} = Accounts.login("codex", "remote", [token: "sk-codex-remote"], opts)
    {:ok, lease} = Store.acquire("codex", Store.credential_ref(account), Keyword.put(opts, :run_id, "run-codex-remote"))

    config = ProviderConfig.new(%{kind: "codex", options: %{"credential_ref" => Store.credential_ref(account)}})

    assert {:ok, material} =
             Codex.Adapter.materialize_credential(
               config,
               lease,
               opts ++
                 [
                   provider_runtime_context: %{worker_placement: "ssh"},
                   codex_remote_credential_root: "/tmp/symphony-codex-test"
                 ]
             )

    codex_home = material.env["CODEX_HOME"]
    assert String.starts_with?(codex_home, "/tmp/symphony-codex-test/")
    refute Map.has_key?(material.env, "OPENAI_API_KEY")
    refute File.exists?(codex_home)

    {setup_commands, cleanup_commands} = Codex.Credential.remote_auth_commands(material)
    setup = Enum.join(setup_commands, "\n")

    assert setup =~ "auth.json"
    assert setup =~ "cli_auth_credentials_store"
    assert setup =~ "\"OPENAI_API_KEY\""
    refute setup =~ "OPENAI_API_KEY="
    assert Enum.any?(cleanup_commands, &String.contains?(&1, "rm -rf"))
  end

  test "unsupported Codex credential kinds fail explicitly" do
    lease =
      Lease.new(%{
        id: "lease-unsupported",
        provider_kind: "codex",
        metadata: %{account: %{credential_kind: "codex_oauth_cache"}}
      })

    assert {:error, {:unsupported_codex_credential_kind, "codex_oauth_cache"}} =
             Codex.Adapter.materialize_credential(ProviderConfig.new(%{kind: "codex", options: %{}}), lease, [])
  end

  defp assert_mode(path, expected_mode) do
    if match?({:unix, _}, :os.type()) do
      assert (File.stat!(path).mode &&& 0o777) == expected_mode
    end
  end

  defp temp_root!(suffix) do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphony-codex-credential-test-#{suffix}-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(root) end)
    root
  end

  defp store_opts(store_root) do
    [agent_credentials: %{enabled: true, store_root: store_root, exhausted_cooldown_ms: 60_000}]
  end
end
