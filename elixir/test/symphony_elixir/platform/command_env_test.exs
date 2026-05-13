defmodule SymphonyElixir.Platform.CommandEnvTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Platform.CommandEnv

  @test_token_env "SYMPHONY_COMMAND_ENV_TEST_TOKEN"

  setup do
    previous = System.get_env(@test_token_env)
    System.put_env(@test_token_env, "secret-token")

    on_exit(fn ->
      case previous do
        nil -> System.delete_env(@test_token_env)
        value -> System.put_env(@test_token_env, value)
      end
    end)

    :ok
  end

  test "system_cmd clears sensitive environment variables by default" do
    assert {output, 0} = shell_env_probe()
    assert output == "cleared"
  end

  test "system_cmd preserves explicitly allowed sensitive environment variables" do
    assert {output, 0} = shell_env_probe(allow_sensitive_env: [@test_token_env])
    assert output == "present"
  end

  test "merge lets explicit environment values override scrubbed entries" do
    env = CommandEnv.merge(%{@test_token_env => "explicit-token"})

    assert {@test_token_env, "explicit-token"} in env
  end

  defp shell_env_probe(opts \\ []) do
    sh = System.find_executable("sh") || flunk("sh executable is required")

    CommandEnv.system_cmd(
      sh,
      ["-c", "if [ -z \"${#{@test_token_env}+x}\" ]; then printf cleared; else printf present; fi"],
      opts
    )
  end
end
