defmodule SymphonyElixir.Workflow.Extension.Runtime.Options do
  @moduledoc """
  Runtime option normalization for workflow extension execution.

  This module owns the `runtime_extension_opts` shape consumed by the runtime
  dispatcher. It accepts Elixir atom keys and string keys only at this boundary.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.Runtime.Error

  @common_opts_key :common
  @common_opts_string_key "common"

  @type extension_opts :: keyword() | %{optional(module() | String.t() | :common) => keyword()}

  @spec by_extension([map()], keyword()) :: {:ok, %{String.t() => keyword()}} | {:error, map()}
  def by_extension(entries, opts) when is_list(entries) and is_list(opts) do
    opts
    |> Keyword.get(:extension_opts, [])
    |> validate(entries)
    |> case do
      {:ok, extension_opts} ->
        {:ok, Map.new(entries, fn entry -> {entry.id, extension_opts(extension_opts, entry)} end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec registry_opts(keyword()) :: keyword()
  def registry_opts(opts) when is_list(opts) do
    opts
    |> Keyword.take([:entries, :extra_entries, :sources, :extra_sources, :source_opts])
    |> case do
      [] -> []
      registry_opts -> registry_opts
    end
  end

  @spec common_keys() :: [atom() | String.t()]
  def common_keys, do: [@common_opts_key, @common_opts_string_key]

  @spec common_key() :: atom()
  def common_key, do: @common_opts_key

  @spec common_string_key() :: String.t()
  def common_string_key, do: @common_opts_string_key

  defp validate(nil, _entries), do: {:ok, []}

  defp validate(opts, _entries) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, opts}
    else
      {:error, Error.options(:extension_opts_not_keyword, opts_type: Diagnostics.type_name(opts))}
    end
  end

  defp validate(%{} = opts, entries) do
    with :ok <- validate_keys(opts, entries),
         :ok <- validate_values(opts) do
      {:ok, opts}
    end
  end

  defp validate(opts, _entries) do
    {:error, Error.options(:extension_opts_not_keyword_or_map, opts_type: Diagnostics.type_name(opts))}
  end

  defp validate_keys(opts, entries) do
    allowed_keys = allowed_keys(entries)

    unknown_keys =
      opts
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(allowed_keys, &1))

    case unknown_keys do
      [] ->
        :ok

      keys ->
        {:error,
         Error.options(:unknown_extension_opts_keys,
           keys: Enum.map(keys, &inspect/1),
           allowed_keys: allowed_key_diagnostics(entries)
         )}
    end
  end

  defp validate_values(opts) do
    invalid_values =
      opts
      |> Enum.reject(fn {_key, value} -> Keyword.keyword?(value) end)

    case invalid_values do
      [] ->
        :ok

      [{key, value} | _rest] ->
        {:error,
         Error.options(:invalid_extension_opts_value,
           key: inspect(key),
           value_type: Diagnostics.type_name(value)
         )}
    end
  end

  defp extension_opts(opts, _entry) when is_list(opts), do: opts

  defp extension_opts(%{} = opts, entry) do
    opts
    |> common_opts()
    |> Keyword.merge(module_opts(opts, entry.module))
    |> Keyword.merge(id_opts(opts, entry.id))
  end

  defp common_opts(opts) do
    opts_for_key(opts, @common_opts_key) ++ opts_for_key(opts, @common_opts_string_key)
  end

  defp module_opts(opts, extension), do: opts_for_key(opts, extension) ++ opts_for_key(opts, inspect(extension))
  defp id_opts(opts, extension_id), do: opts_for_key(opts, extension_id)

  defp opts_for_key(opts, key) do
    case Map.get(opts, key, []) do
      value when is_list(value) -> value
      _value -> []
    end
  end

  defp allowed_keys(entries) do
    entries
    |> Enum.flat_map(fn entry -> [entry.module, inspect(entry.module), entry.id] end)
    |> Kernel.++(common_keys())
    |> MapSet.new()
  end

  defp allowed_key_diagnostics(entries) do
    entries
    |> Enum.flat_map(fn entry -> [inspect(entry.module), inspect(inspect(entry.module)), inspect(entry.id)] end)
    |> Kernel.++(Enum.map(common_keys(), &inspect/1))
    |> Enum.uniq()
    |> Enum.sort()
  end
end
