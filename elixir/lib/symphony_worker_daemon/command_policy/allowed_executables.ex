defmodule SymphonyWorkerDaemon.CommandPolicy.AllowedExecutables do
  @moduledoc false

  alias SymphonyElixir.PathSafety
  alias SymphonyElixir.Platform.Process, as: PlatformProcess

  @type executable_spec :: %{
          required(String.t()) => String.t() | boolean()
        }

  @spec prepare([term()]) :: {:ok, [executable_spec()]} | {:error, term()}
  def prepare(entries) when is_list(entries) do
    entries
    |> Enum.map(&normalize_entry/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn command, {:ok, acc} ->
      case resolve(command) do
        {:ok, spec} -> {:cont, {:ok, [spec | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, specs} -> {:ok, Enum.reverse(specs)}
      {:error, reason} -> {:error, reason}
    end
  end

  def prepare(_entries), do: {:error, :allowed_executables_invalid}

  @spec allowed_specs(keyword()) :: {:ok, [executable_spec()]} | {:error, term()}
  def allowed_specs(opts) when is_list(opts) do
    opts
    |> Keyword.get(:allowed_executables, [])
    |> case do
      specs when is_list(specs) ->
        if Enum.all?(specs, &prepared_spec?/1) do
          {:ok, specs}
        else
          prepare(specs)
        end

      _value ->
        {:error, :allowed_executables_invalid}
    end
  end

  @spec resolve(String.t()) :: {:ok, executable_spec()} | {:error, term()}
  def resolve(command) when is_binary(command) do
    case PlatformProcess.resolve_executable(command, File.cwd!()) do
      {:ok, resolved_path} ->
        with {:ok, canonical_path} <- canonical_path(resolved_path) do
          {:ok,
           %{
             "command" => command,
             "name" => Path.basename(resolved_path),
             "path" => resolved_path,
             "canonical_path" => canonical_path
           }}
        end

      {:error, reason} ->
        {:error, {:allowed_executable_unavailable, command, reason}}
    end
  end

  @spec canonical_path(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def canonical_path(path) when is_binary(path) do
    case PathSafety.canonicalize(path) do
      {:ok, canonical_path} -> {:ok, canonical_path}
      {:error, reason} -> {:error, {:executable_path_unavailable, path, reason}}
    end
  end

  @spec matches?(executable_spec(), String.t(), Path.t()) :: boolean()
  def matches?(%{"canonical_path" => allowed_path}, _command, resolved_path) when is_binary(allowed_path) do
    resolved_path == allowed_path
  end

  def matches?(%{"path" => allowed_path}, _command, resolved_path) when is_binary(allowed_path) do
    case canonical_path(allowed_path) do
      {:ok, canonical_path} -> resolved_path == canonical_path
      {:error, _reason} -> resolved_path == allowed_path
    end
  end

  def matches?(_spec, _command, _resolved_path), do: false

  @spec normalize_entry(term()) :: String.t() | nil
  def normalize_entry(nil), do: nil

  def normalize_entry(%{"command" => command}) when is_binary(command), do: normalize_entry(command)

  def normalize_entry(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      command -> command
    end
  end

  def normalize_entry(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_entry()
  def normalize_entry(_value), do: nil

  defp prepared_spec?(%{"command" => command, "path" => path, "name" => name})
       when is_binary(command) and is_binary(path) and is_binary(name),
       do: true

  defp prepared_spec?(_entry), do: false
end
