defmodule SymphonyElixir.CLI.Accounts.TokenSource do
  @moduledoc false

  @type parse_error :: %OptionParser.ParseError{}

  @spec resolve_login_opts(keyword()) :: {:ok, keyword()} | {:error, String.t() | parse_error()}
  def resolve_login_opts(opts) do
    token_sources =
      [
        Keyword.has_key?(opts, :token),
        Keyword.get(opts, :token_stdin, false),
        Keyword.has_key?(opts, :token_file),
        Keyword.has_key?(opts, :token_env)
      ]
      |> Enum.count(& &1)

    cond do
      token_sources > 1 ->
        {:error, %OptionParser.ParseError{message: "Pass only one of --token, --token-stdin, --token-file, or --token-env"}}

      Keyword.get(opts, :token_stdin, false) ->
        {:ok, opts |> Keyword.delete(:token_stdin) |> Keyword.put(:token, stdin_token())}

      token_file = Keyword.get(opts, :token_file) ->
        read_token_file(opts, token_file)

      token_env = Keyword.get(opts, :token_env) ->
        read_token_env(opts, token_env)

      true ->
        {:ok, opts}
    end
  end

  defp stdin_token do
    :stdio
    |> IO.read(:eof)
    |> to_string()
    |> String.trim()
  end

  defp read_token_file(opts, token_file) do
    case File.read(Path.expand(token_file)) do
      {:ok, token} ->
        {:ok, opts |> Keyword.delete(:token_file) |> Keyword.put(:token, String.trim(token))}

      {:error, reason} ->
        {:error, "Unable to read token file #{Path.expand(token_file)}: #{:file.format_error(reason)}"}
    end
  end

  defp read_token_env(opts, token_env) do
    case System.get_env(token_env) do
      token when is_binary(token) and token != "" ->
        {:ok, opts |> Keyword.delete(:token_env) |> Keyword.put(:token, String.trim(token))}

      _token ->
        {:error, "Environment variable #{token_env} is not set or is empty"}
    end
  end
end
