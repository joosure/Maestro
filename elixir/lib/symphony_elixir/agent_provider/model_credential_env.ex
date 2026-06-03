defmodule SymphonyElixir.AgentProvider.ModelCredentialEnv do
  @moduledoc """
  Shared model-service credential environment variable names.

  These names are not owned by a single agent provider. Providers such as
  Codex, Claude Code, and OpenCode may use the same upstream model-service
  API-key conventions in different credential flows.
  """

  @anthropic_api_key_env "ANTHROPIC_API_KEY"
  @google_generative_ai_api_key_env "GOOGLE_GENERATIVE_AI_API_KEY"
  @openai_api_key_env "OPENAI_API_KEY"
  @openrouter_api_key_env "OPENROUTER_API_KEY"
  @zai_api_key_env "ZAI_API_KEY"

  @spec anthropic_api_key_env() :: String.t()
  def anthropic_api_key_env, do: @anthropic_api_key_env

  @spec google_generative_ai_api_key_env() :: String.t()
  def google_generative_ai_api_key_env, do: @google_generative_ai_api_key_env

  @spec openai_api_key_env() :: String.t()
  def openai_api_key_env, do: @openai_api_key_env

  @spec openrouter_api_key_env() :: String.t()
  def openrouter_api_key_env, do: @openrouter_api_key_env

  @spec zai_api_key_env() :: String.t()
  def zai_api_key_env, do: @zai_api_key_env
end
