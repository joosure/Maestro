defmodule SymphonyElixir.CLI.Accounts.Parser do
  @moduledoc false

  @type parse_error :: %OptionParser.ParseError{}

  @spec parse_options([String.t()], String.t(), keyword()) ::
          {:ok, keyword(), String.t() | nil} | {:error, parse_error()}
  def parse_options(args, usage, switches) do
    case OptionParser.parse(args, strict: Keyword.put_new(switches, :config, :string)) do
      {opts, args, []} when length(args) <= 1 ->
        with {:ok, workflow_path} <- workflow_path(opts, args) do
          {:ok, Keyword.delete(opts, :config), workflow_path}
        end

      {_opts, _args, invalid} when invalid != [] ->
        {:error, %OptionParser.ParseError{message: "Invalid account option: #{inspect(invalid)}"}}

      _result ->
        {:error, %OptionParser.ParseError{message: usage}}
    end
  end

  @spec parse_list_options([String.t()], String.t()) ::
          {:ok, String.t() | nil, String.t() | nil} | {:error, parse_error()}
  def parse_list_options(args, usage) do
    case OptionParser.parse(args, strict: [config: :string]) do
      {opts, args, []} when length(args) <= 2 ->
        parse_list_args(opts, args)

      {_opts, _args, invalid} when invalid != [] ->
        {:error, %OptionParser.ParseError{message: "Invalid account option: #{inspect(invalid)}"}}

      _result ->
        {:error, %OptionParser.ParseError{message: usage}}
    end
  end

  @spec parse_lease_list_options([String.t()], String.t()) ::
          {:ok, String.t() | nil, String.t() | nil, String.t() | nil} | {:error, parse_error()}
  def parse_lease_list_options(args, usage) do
    case OptionParser.parse(args, strict: [config: :string]) do
      {opts, args, []} when length(args) <= 3 ->
        parse_lease_list_args(opts, args)

      {_opts, _args, invalid} when invalid != [] ->
        {:error, %OptionParser.ParseError{message: "Invalid account option: #{inspect(invalid)}"}}

      _result ->
        {:error, %OptionParser.ParseError{message: usage}}
    end
  end

  @spec parse_lease_release_options([String.t()], String.t()) ::
          {:ok, String.t(), String.t(), String.t(), String.t() | nil} | {:error, parse_error()}
  def parse_lease_release_options(args, usage) do
    case OptionParser.parse(args, strict: [config: :string]) do
      {opts, [provider_kind, id, lease_id], []} ->
        with {:ok, workflow_path} <- workflow_path(opts, []) do
          {:ok, provider_kind, id, lease_id, workflow_path}
        end

      {opts, [provider_kind, id, lease_id, workflow_path_arg], []} ->
        with {:ok, workflow_path} <- workflow_path(opts, [workflow_path_arg]) do
          {:ok, provider_kind, id, lease_id, workflow_path}
        end

      {_opts, _args, invalid} when invalid != [] ->
        {:error, %OptionParser.ParseError{message: "Invalid account option: #{inspect(invalid)}"}}

      _result ->
        {:error, %OptionParser.ParseError{message: usage}}
    end
  end

  defp parse_list_args(opts, []) do
    with {:ok, workflow_path} <- workflow_path(opts, []) do
      {:ok, nil, workflow_path}
    end
  end

  defp parse_list_args(opts, [provider_kind]) do
    if workflow_path_arg?(provider_kind) do
      with {:ok, workflow_path} <- workflow_path(opts, [provider_kind]) do
        {:ok, nil, workflow_path}
      end
    else
      with {:ok, workflow_path} <- workflow_path(opts, []) do
        {:ok, provider_kind, workflow_path}
      end
    end
  end

  defp parse_list_args(opts, [provider_kind, workflow_path_arg]) do
    with {:ok, workflow_path} <- workflow_path(opts, [workflow_path_arg]) do
      {:ok, provider_kind, workflow_path}
    end
  end

  defp parse_lease_list_args(opts, []) do
    with {:ok, workflow_path} <- workflow_path(opts, []) do
      {:ok, nil, nil, workflow_path}
    end
  end

  defp parse_lease_list_args(opts, [provider_kind]) do
    if workflow_path_arg?(provider_kind) do
      with {:ok, workflow_path} <- workflow_path(opts, [provider_kind]) do
        {:ok, nil, nil, workflow_path}
      end
    else
      with {:ok, workflow_path} <- workflow_path(opts, []) do
        {:ok, provider_kind, nil, workflow_path}
      end
    end
  end

  defp parse_lease_list_args(opts, [provider_kind, id]) do
    with {:ok, workflow_path} <- workflow_path(opts, []) do
      {:ok, provider_kind, id, workflow_path}
    end
  end

  defp parse_lease_list_args(opts, [provider_kind, id, workflow_path_arg]) do
    with {:ok, workflow_path} <- workflow_path(opts, [workflow_path_arg]) do
      {:ok, provider_kind, id, workflow_path}
    end
  end

  defp workflow_path_arg?(arg) when is_binary(arg) do
    String.contains?(arg, ["/", "\\"]) or String.downcase(Path.extname(arg)) == ".md"
  end

  defp workflow_path(opts, args) do
    config_opt = Keyword.get(opts, :config)
    trailing_path = List.first(args)

    cond do
      is_binary(config_opt) and is_binary(trailing_path) ->
        {:error, %OptionParser.ParseError{message: "Pass account config path either as --config or trailing path, not both"}}

      is_binary(config_opt) ->
        {:ok, config_opt}

      is_binary(trailing_path) ->
        {:ok, trailing_path}

      true ->
        {:ok, nil}
    end
  end
end
