defmodule SymphonyWorkerDaemon.CommandPolicy do
  @moduledoc false

  alias SymphonyElixir.Platform.Process, as: PlatformProcess
  alias SymphonyWorkerDaemon.CommandPolicy.{AllowedExecutables, Capabilities, Validation}
  alias SymphonyWorkerDaemon.Protocol.Fields, as: ProtocolFields

  @mode_key ProtocolFields.mode()
  @argv_key ProtocolFields.argv()

  @type executable_spec :: %{
          required(String.t()) => String.t() | boolean()
        }

  @spec validate(map(), Path.t(), keyword()) :: :ok | {:error, term()}
  def validate(%{@mode_key => "argv", @argv_key => [command | _args]}, cwd, opts)
      when is_binary(command) and is_binary(cwd) and is_list(opts) do
    if Keyword.get(opts, :allow_any_executable?, false) do
      :ok
    else
      with {:ok, resolved_path} <- PlatformProcess.resolve_executable(command, cwd),
           {:ok, canonical_path} <- AllowedExecutables.canonical_path(resolved_path),
           :ok <- Validation.executable_allowed?(command, canonical_path, opts) do
        :ok
      end
    end
  end

  def validate(%{@mode_key => "shell"}, _cwd, opts) when is_list(opts) do
    cond do
      not Keyword.get(opts, :allow_shell?, false) ->
        {:error, :shell_command_disabled}

      Keyword.get(opts, :allow_any_executable?, false) ->
        :ok

      true ->
        {:error, :shell_command_requires_allow_any_executable}
    end
  end

  def validate(%{@mode_key => "unset"}, _cwd, _opts), do: {:error, :command_unset}
  def validate(_command, _cwd, _opts), do: {:error, :command_invalid}

  @spec prepare_allowed_executables([term()]) :: {:ok, [executable_spec()]} | {:error, term()}
  defdelegate prepare_allowed_executables(entries), to: AllowedExecutables, as: :prepare

  @spec capabilities(keyword()) :: [map()]
  defdelegate capabilities(opts), to: Capabilities, as: :build
end
