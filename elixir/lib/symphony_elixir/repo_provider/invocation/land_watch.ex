defmodule SymphonyElixir.RepoProvider.Invocation.LandWatch do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Invocation

  @spec parse([String.t()], Invocation.t()) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse([], invocation), do: {:ok, invocation}

  def parse(["--poll-ms", raw_ms | rest], invocation) do
    with {:ok, ms} <- positive_integer(raw_ms, "Invalid pr-land-watch poll milliseconds") do
      parse(rest, %{invocation | poll_ms: ms})
    end
  end

  def parse(["--poll-ms"], _invocation) do
    {:error, Error.invalid_invocation("Option --poll-ms requires a value")}
  end

  def parse(["--checks-appear-timeout-ms", raw_ms | rest], invocation) do
    with {:ok, ms} <- positive_integer(raw_ms, "Invalid pr-land-watch checks appear timeout milliseconds") do
      parse(rest, %{invocation | checks_appear_timeout_ms: ms})
    end
  end

  def parse(["--checks-appear-timeout-ms"], _invocation) do
    {:error, Error.invalid_invocation("Option --checks-appear-timeout-ms requires a value")}
  end

  def parse([number | rest], %Invocation{number: nil} = invocation) when is_binary(number) do
    if String.starts_with?(number, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-land-watch option: #{number}")}
    else
      parse(rest, %{invocation | number: number})
    end
  end

  def parse([arg | _rest], _invocation) when is_binary(arg) do
    if String.starts_with?(arg, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-land-watch option: #{arg}")}
    else
      {:error, Error.invalid_invocation("Unexpected pr-land-watch argument: #{arg}")}
    end
  end

  defp positive_integer(raw, error_prefix) do
    case Integer.parse(raw) do
      {value, ""} when value > 0 -> {:ok, value}
      _other -> {:error, Error.invalid_invocation("#{error_prefix}: #{raw}")}
    end
  end
end
