defmodule SymphonyElixir.AgentProvider.ModelCredentialEnvTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.AgentProvider.ModelCredentialEnv

  test "exposes shared model-service API key environment names" do
    assert ModelCredentialEnv.anthropic_api_key_env() == "ANTHROPIC_API_KEY"
    assert ModelCredentialEnv.google_generative_ai_api_key_env() == "GOOGLE_GENERATIVE_AI_API_KEY"
    assert ModelCredentialEnv.openai_api_key_env() == "OPENAI_API_KEY"
    assert ModelCredentialEnv.openrouter_api_key_env() == "OPENROUTER_API_KEY"
    assert ModelCredentialEnv.zai_api_key_env() == "ZAI_API_KEY"
  end
end
