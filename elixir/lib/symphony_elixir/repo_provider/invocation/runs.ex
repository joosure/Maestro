defmodule SymphonyElixir.RepoProvider.Invocation.Runs do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Invocation
  alias SymphonyElixir.RepoProvider.Invocation.Options

  @spec parse_list([String.t()], Invocation.t()) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse_list([], invocation), do: {:ok, invocation}

  def parse_list(["--branch", branch | rest], invocation) do
    parse_list(rest, %{invocation | branch: branch})
  end

  def parse_list(["--branch"], _invocation) do
    {:error, Error.invalid_invocation("Option --branch requires a value")}
  end

  def parse_list([flag, raw_limit | rest], invocation) when flag in ["--limit", "-L"] do
    case Integer.parse(raw_limit) do
      {limit, ""} when limit > 0 ->
        parse_list(rest, %{invocation | limit: limit})

      _other ->
        {:error, Error.invalid_invocation("Invalid run-list limit: #{raw_limit}")}
    end
  end

  def parse_list([flag], _invocation) when flag in ["--limit", "-L"] do
    {:error, Error.invalid_invocation("Option #{flag} requires a value")}
  end

  def parse_list(["--json", fields | rest], invocation) do
    parse_list(rest, %{invocation | json_fields: Options.fields(fields)})
  end

  def parse_list(["--json"], _invocation) do
    {:error, Error.invalid_invocation("Option --json requires a value")}
  end

  def parse_list([flag, expr | rest], invocation) when flag in ["-q", "--jq"] do
    parse_list(rest, %{invocation | jq: expr})
  end

  def parse_list([flag], _invocation) when flag in ["-q", "--jq"] do
    {:error, Error.invalid_invocation("Option #{flag} requires a value")}
  end

  def parse_list([arg | _rest], _invocation) do
    {:error, Error.invalid_invocation("Unsupported run-list option: #{arg}")}
  end

  @spec parse_view([String.t()], Invocation.t()) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse_view([], %Invocation{run_id: nil}) do
    {:error, Error.invalid_invocation("run-view requires a run id")}
  end

  def parse_view([], invocation), do: {:ok, invocation}

  def parse_view(["--log" | rest], invocation) do
    parse_view(rest, %{invocation | log?: true})
  end

  def parse_view(["--json", fields | rest], invocation) do
    parse_view(rest, %{invocation | json_fields: Options.fields(fields)})
  end

  def parse_view(["--json"], _invocation) do
    {:error, Error.invalid_invocation("Option --json requires a value")}
  end

  def parse_view([flag, expr | rest], invocation) when flag in ["-q", "--jq"] do
    parse_view(rest, %{invocation | jq: expr})
  end

  def parse_view([flag], _invocation) when flag in ["-q", "--jq"] do
    {:error, Error.invalid_invocation("Option #{flag} requires a value")}
  end

  def parse_view([run_id | rest], %Invocation{run_id: nil} = invocation)
      when is_binary(run_id) do
    if String.starts_with?(run_id, "-") do
      {:error, Error.invalid_invocation("Unsupported run-view option: #{run_id}")}
    else
      parse_view(rest, %{invocation | run_id: run_id})
    end
  end

  def parse_view([arg | _rest], _invocation) do
    {:error, Error.invalid_invocation("Unexpected run-view argument: #{arg}")}
  end
end
