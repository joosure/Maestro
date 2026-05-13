defmodule SymphonyElixir.RepoProvider.Invocation.Api do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Invocation

  @spec parse([String.t()], Invocation.t()) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse([], %Invocation{api_endpoint: nil}) do
    {:error, Error.invalid_invocation("repo-provider api requires an endpoint")}
  end

  def parse([], invocation), do: {:ok, invocation}

  def parse([flag, method | rest], invocation) when flag in ["--method", "-X"] do
    parse(rest, %{invocation | api_method: String.upcase(method)})
  end

  def parse([flag], _invocation) when flag in ["--method", "-X"] do
    {:error, Error.invalid_invocation("Option #{flag} requires a value")}
  end

  def parse([flag, expr | rest], invocation) when flag in ["--jq", "-q"] do
    parse(rest, %{invocation | jq: expr})
  end

  def parse([flag], _invocation) when flag in ["--jq", "-q"] do
    {:error, Error.invalid_invocation("Option #{flag} requires a value")}
  end

  def parse([flag, field | rest], invocation) when flag in ["-f", "-F"] do
    case String.split(field, "=", parts: 2) do
      [key, value] ->
        parse(rest, %{invocation | api_fields: Map.put(invocation.api_fields, key, value)})

      _other ->
        {:error, Error.invalid_invocation("Expected key=value field, got: #{field}")}
    end
  end

  def parse([flag], _invocation) when flag in ["-f", "-F"] do
    {:error, Error.invalid_invocation("Option #{flag} requires a value")}
  end

  def parse([arg | rest], %Invocation{api_endpoint: nil} = invocation) do
    if String.starts_with?(arg, "-") do
      {:error, Error.invalid_invocation("Unsupported api option: #{arg}")}
    else
      parse(rest, %{invocation | api_endpoint: arg})
    end
  end

  def parse([arg | _rest], _invocation) do
    {:error, Error.invalid_invocation("Unexpected api argument: #{arg}")}
  end
end
