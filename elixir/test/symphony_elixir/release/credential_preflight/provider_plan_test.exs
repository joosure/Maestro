defmodule SymphonyElixir.Release.CredentialPreflight.ProviderPlanTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.AgentProvider.ReleaseCredentialPreflight, as: ProviderPreflight
  alias SymphonyElixir.AgentProvider.ReleaseCredentialPreflight.LoginPlan
  alias SymphonyElixir.Release.CredentialPreflight.ProviderPlan

  setup do
    original_adapters = Application.get_env(:symphony_elixir, :agent_provider_adapters, :missing)

    on_exit(fn ->
      case original_adapters do
        :missing -> Application.delete_env(:symphony_elixir, :agent_provider_adapters)
        adapters -> Application.put_env(:symphony_elixir, :agent_provider_adapters, adapters)
      end
    end)
  end

  test "builds CodeBuddy login plan from trimmed token env override" do
    {:ok, plan} = ProviderPlan.fetch("codebuddy_code")

    env = %{
      "SYMPHONY_CODEBUDDY_TOKEN_ENV" => " CODEBUDDY_CUSTOM_KEY ",
      "CODEBUDDY_CUSTOM_KEY" => "ck-custom",
      "CODEBUDDY_INTERNET_ENVIRONMENT" => " internal "
    }

    assert {:ok, login_plan} = ProviderPlan.login_plan(plan, "default", env)
    assert login_plan.token_env == "CODEBUDDY_CUSTOM_KEY"
    assert login_plan.login_opts == [internet_environment: "internal", token: "ck-custom"]
  end

  test "builds OpenCode login plan from custom env-name and token env" do
    {:ok, plan} = ProviderPlan.fetch("opencode")

    env = %{
      "SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME" => " CUSTOM_API_KEY ",
      "SYMPHONY_OPENCODE_TOKEN_ENV" => " CUSTOM_TOKEN ",
      "CUSTOM_TOKEN" => "secret"
    }

    assert {:ok, login_plan} = ProviderPlan.login_plan(plan, "custom", env)
    assert login_plan.token_env == "CUSTOM_TOKEN"
    assert login_plan.login_opts == [env_name: "CUSTOM_API_KEY", token: "secret"]
  end

  test "builds Codex login plan from OpenAI API key" do
    {:ok, plan} = ProviderPlan.fetch("codex")

    assert {:ok, login_plan} = ProviderPlan.login_plan(plan, "default", %{"OPENAI_API_KEY" => "sk-test"})
    assert login_plan.token_env == "OPENAI_API_KEY"
    assert login_plan.login_opts == [token: "sk-test"]
  end

  test "builds Claude Code login plan from OAuth token" do
    {:ok, plan} = ProviderPlan.fetch("claude_code")

    assert {:ok, login_plan} =
             ProviderPlan.login_plan(plan, "default", %{"CLAUDE_CODE_OAUTH_TOKEN" => "oauth-token"})

    assert login_plan.token_env == "CLAUDE_CODE_OAUTH_TOKEN"
    assert login_plan.login_opts == [token: "oauth-token"]
  end

  test "explains unknown OpenCode accounts when no token env exists" do
    {:ok, plan} = ProviderPlan.fetch("opencode")

    assert {:ok, login_plan} = ProviderPlan.login_plan(plan, "custom", %{})
    assert login_plan.login_opts == nil
    assert login_plan.token_env == "SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME"

    assert login_plan.credential_hint =~
             "set SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME to the environment variable name OpenCode should receive"
  end

  test "rejects invalid OpenCode credential env names" do
    {:ok, plan} = ProviderPlan.fetch("opencode")

    assert {:error, message} =
             ProviderPlan.login_plan(plan, "custom", %{
               "SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME" => "1 BAD"
             })

    assert message == ~s(SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME must contain an environment variable name, got "1 BAD")
  end

  test "rejects invalid token env names" do
    {:ok, plan} = ProviderPlan.fetch("codebuddy_code")

    assert {:error, message} =
             ProviderPlan.login_plan(plan, "default", %{
               "SYMPHONY_CODEBUDDY_TOKEN_ENV" => "1 BAD"
             })

    assert message == ~s(SYMPHONY_CODEBUDDY_TOKEN_ENV must contain an environment variable name, got "1 BAD")
  end

  test "builds auth probe verify opts with prompt, model, and command override" do
    {:ok, plan} = ProviderPlan.fetch("opencode")

    env = %{
      ProviderPreflight.verify_prompt_env() => " Reply OK. ",
      "SYMPHONY_OPENCODE_VERIFY_COMMAND" => " opencode-beta "
    }

    settings = %{
      agent_provider: %{
        options: %{
          model: " openrouter/test-model "
        }
      }
    }

    assert {:ok, opts} = ProviderPlan.verify_opts(plan, env, settings)
    assert Keyword.fetch!(opts, :auth_probe)
    assert Keyword.fetch!(opts, :prompt) == "Reply OK."
    assert Keyword.fetch!(opts, :model) == "openrouter/test-model"
    assert Keyword.fetch!(opts, :command) == "opencode-beta"
  end

  test "builds command-only verify opts" do
    {:ok, plan} = ProviderPlan.fetch("opencode")

    assert {:ok, []} =
             ProviderPlan.verify_opts(
               plan,
               %{ProviderPreflight.verify_mode_env() => " command "},
               %{}
             )
  end

  test "builds command-backed verify opts for Codex and Claude Code" do
    {:ok, codex_plan} = ProviderPlan.fetch("codex")
    {:ok, claude_plan} = ProviderPlan.fetch("claude_code")

    assert {:ok, [command: "codex-beta"]} =
             ProviderPlan.verify_opts(codex_plan, %{"SYMPHONY_CODEX_VERIFY_COMMAND" => " codex-beta "}, %{})

    assert {:ok, [command: "claude-beta"]} =
             ProviderPlan.verify_opts(
               claude_plan,
               %{"SYMPHONY_CLAUDE_CODE_VERIFY_COMMAND" => " claude-beta "},
               %{}
             )
  end

  test "discovers provider plans from adapter callbacks" do
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{
      "test_callback_provider" => __MODULE__.CallbackAdapter
    })

    assert {:ok, __MODULE__.CallbackPlan} = ProviderPlan.fetch("test_callback_provider")

    assert {:ok, login_plan} = ProviderPlan.login_plan(__MODULE__.CallbackPlan, "default", %{})
    assert %LoginPlan{} = login_plan
    assert login_plan.credential_hint == "test hint"
    assert login_plan.login_opts == [account_id: "default"]
    assert login_plan.token_env == "TEST_TOKEN"

    assert {:ok, [command: "test-agent"]} = ProviderPlan.verify_opts(__MODULE__.CallbackPlan, %{}, %{})
  end

  test "normalizes legacy map login plans returned by provider callbacks" do
    assert {:ok, login_plan} = ProviderPlan.login_plan(__MODULE__.MapPlan, "default", %{})

    assert %LoginPlan{} = login_plan
    assert login_plan.credential_hint == "map hint"
    assert login_plan.login_opts == [account_id: "default"]
    assert login_plan.token_env == "MAP_TOKEN"
  end

  test "reports malformed login plans returned by provider callbacks" do
    assert {:error, message} = ProviderPlan.login_plan(__MODULE__.MalformedLoginPlan, "default", %{})

    assert message =~ "invalid login plan from #{inspect(__MODULE__.MalformedLoginPlan)}"
    assert message =~ "login plan login_opts must be a keyword list or nil"
  end

  test "reports malformed verify opts returned by provider callbacks" do
    assert {:error, message} = ProviderPlan.verify_opts(__MODULE__.MalformedVerifyPlan, %{}, %{})

    assert message =~ "invalid verify opts from #{inspect(__MODULE__.MalformedVerifyPlan)}"
    assert message =~ "expected keyword list"
  end

  test "reports unexpected provider callback results" do
    assert {:error, message} = ProviderPlan.login_plan(__MODULE__.UnexpectedLoginReturnPlan, "default", %{})

    assert message =~ "login plan from #{inspect(__MODULE__.UnexpectedLoginReturnPlan)} returned :ok"
    assert message =~ "expected {:ok, plan} or {:error, reason}"
  end

  test "reports provider callback plans with mismatched provider kind as implementation errors" do
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{
      "bad_provider" => __MODULE__.MismatchedAdapter
    })

    assert {:error, message} = ProviderPlan.fetch("bad_provider")

    assert message =~ "invalid release credential preflight plan for bad_provider"
    assert message =~ inspect(__MODULE__.MismatchedAdapter)
    assert message =~ "declares provider_kind \"other_provider\", expected \"bad_provider\""
  end

  test "reports provider callback plans missing required callbacks as implementation errors" do
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{
      "incomplete_provider" => __MODULE__.IncompleteAdapter
    })

    assert {:error, message} = ProviderPlan.fetch("incomplete_provider")

    assert message =~ "invalid release credential preflight plan for incomplete_provider"
    assert message =~ inspect(__MODULE__.IncompleteAdapter)
    assert message =~ "missing callbacks: login_plan/2, verify_opts/2"
  end

  test "reports invalid provider callback return values as implementation errors" do
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{
      "invalid_return_provider" => __MODULE__.InvalidReturnAdapter
    })

    assert {:error, message} = ProviderPlan.fetch("invalid_return_provider")

    assert message =~ "invalid release credential preflight plan for invalid_return_provider"
    assert message =~ inspect(__MODULE__.InvalidReturnAdapter)
    assert message =~ "expected module or :unsupported from release_credential_preflight_plan/0"
    assert message =~ ~s(got "not-a-module")
  end

  test "rejects unsupported provider plans" do
    assert {:error, message} = ProviderPlan.fetch("mock")

    assert message ==
             "container managed credential preflight supports claude_code, codebuddy_code, codex, opencode, got mock"
  end

  defmodule CallbackAdapter do
    def release_credential_preflight_plan, do: SymphonyElixir.Release.CredentialPreflight.ProviderPlanTest.CallbackPlan
  end

  defmodule MismatchedAdapter do
    def release_credential_preflight_plan, do: SymphonyElixir.Release.CredentialPreflight.ProviderPlanTest.MismatchedPlan
  end

  defmodule IncompleteAdapter do
    def release_credential_preflight_plan, do: SymphonyElixir.Release.CredentialPreflight.ProviderPlanTest.IncompletePlan
  end

  defmodule InvalidReturnAdapter do
    def release_credential_preflight_plan, do: "not-a-module"
  end

  defmodule CallbackPlan do
    @behaviour SymphonyElixir.AgentProvider.ReleaseCredentialPreflight
    alias SymphonyElixir.AgentProvider.ReleaseCredentialPreflight.LoginPlan

    @impl true
    def provider_kind, do: "test_callback_provider"

    @impl true
    def login_plan(account_id, _env_map) do
      LoginPlan.new(%{credential_hint: "test hint", login_opts: [account_id: account_id], token_env: "TEST_TOKEN"})
    end

    @impl true
    def verify_opts(_env_map, _settings), do: {:ok, [command: "test-agent"]}
  end

  defmodule MapPlan do
    def provider_kind, do: "map_provider"

    def login_plan(account_id, _env_map),
      do: {:ok, %{credential_hint: " map hint ", login_opts: [account_id: account_id], token_env: " MAP_TOKEN "}}

    def verify_opts(_env_map, _settings), do: {:ok, []}
  end

  defmodule MalformedLoginPlan do
    def provider_kind, do: "malformed_login_provider"
    def login_plan(_account_id, _env_map), do: {:ok, %{credential_hint: "hint", login_opts: ["bad"], token_env: "TOKEN"}}
    def verify_opts(_env_map, _settings), do: {:ok, []}
  end

  defmodule MalformedVerifyPlan do
    def provider_kind, do: "malformed_verify_provider"
    def login_plan(_account_id, _env_map), do: {:ok, %{credential_hint: "hint", login_opts: nil, token_env: "TOKEN"}}
    def verify_opts(_env_map, _settings), do: {:ok, ["bad"]}
  end

  defmodule UnexpectedLoginReturnPlan do
    def provider_kind, do: "unexpected_login_provider"
    def login_plan(_account_id, _env_map), do: :ok
    def verify_opts(_env_map, _settings), do: {:ok, []}
  end

  defmodule MismatchedPlan do
    def provider_kind, do: "other_provider"
    def login_plan(_account_id, _env_map), do: {:ok, %{credential_hint: "hint", login_opts: nil, token_env: "TOKEN"}}
    def verify_opts(_env_map, _settings), do: {:ok, []}
  end

  defmodule IncompletePlan do
    def provider_kind, do: "incomplete_provider"
  end
end
