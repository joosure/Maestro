defmodule SymphonyElixir.Release.Runner do
  @moduledoc """
  Release entrypoint helpers used by production containers.

  The project still exposes `SymphonyElixir.CLI` as the canonical argument
  evaluator. This module adapts environment-driven container configuration to
  that CLI without requiring Mix or the escript wrapper at runtime.
  """

  alias SymphonyElixir.Release.CredentialPreflight
  alias SymphonyElixir.Release.RuntimeConfig

  @ack_flag "--i-understand-that-this-will-be-running-without-the-usual-guardrails"

  @spec serve_from_env() :: no_return()
  def serve_from_env do
    env_map = System.get_env()

    case CredentialPreflight.run_from_env(env_map) do
      :ok ->
        env_map
        |> serve_args_from_env()
        |> run()

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  @spec serve_args_from_env(map()) :: [String.t()]
  def serve_args_from_env(env_map) when is_map(env_map) do
    env_map
    |> RuntimeConfig.from_env()
    |> serve_args()
  end

  defp serve_args(%RuntimeConfig{} = config) do
    base_args = [
      @ack_flag,
      "--host",
      config.host,
      "--port",
      config.port
    ]

    case config.workflow_source do
      {:template, template} -> base_args ++ ["--template", template]
      {:workflow_path, workflow_path} -> base_args ++ [workflow_path]
    end
  end

  @spec run([String.t()]) :: no_return()
  def run(args) when is_list(args) do
    case SymphonyElixir.CLI.evaluate(args) do
      :ok ->
        wait_for_shutdown()

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  @spec wait_for_shutdown() :: no_return()
  defp wait_for_shutdown do
    case Process.whereis(SymphonyElixir.Supervisor) do
      nil ->
        IO.puts(:stderr, "Symphony supervisor is not running")
        System.halt(1)

      pid ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, reason} ->
            case reason do
              :normal -> System.halt(0)
              _ -> System.halt(1)
            end
        end
    end
  end
end
