defmodule SymphonyWorkerDaemon.Config.Options do
  @moduledoc false

  @spec integer(keyword(), atom(), integer(), integer(), integer()) :: {:ok, integer()} | {:error, String.t()}
  def integer(opts, key, default, min, max) when is_list(opts) and is_atom(key) do
    value = opts |> last_value(key) |> Kernel.||(default)

    if is_integer(value) and value >= min and value <= max do
      {:ok, value}
    else
      {:error, "Worker daemon #{String.replace(to_string(key), "_", "-")} must be an integer between #{min} and #{max}."}
    end
  end

  @spec optional_integer(keyword(), atom(), integer(), integer()) :: {:ok, integer() | nil} | {:error, String.t()}
  def optional_integer(opts, key, min, max) when is_list(opts) and is_atom(key) do
    case last_value(opts, key) do
      nil ->
        {:ok, nil}

      value when is_integer(value) and value >= min and value <= max ->
        {:ok, value}

      _value ->
        {:error, "Worker daemon #{String.replace(to_string(key), "_", "-")} must be an integer between #{min} and #{max}."}
    end
  end

  @spec required_string(keyword(), atom(), term(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def required_string(opts, key, default, label) when is_list(opts) and is_atom(key) and is_binary(label) do
    case opts |> last_value(key) |> normalize_optional_string() do
      value when is_binary(value) -> {:ok, value}
      nil -> normalize_default_string(default, label)
    end
  end

  @spec last_value(keyword(), atom()) :: term()
  def last_value(opts, key) when is_list(opts) and is_atom(key) do
    case Keyword.get_values(opts, key) do
      [] -> nil
      values -> List.last(values)
    end
  end

  @spec normalize_optional_string(term()) :: String.t() | nil
  def normalize_optional_string(nil), do: nil

  def normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  def normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  def normalize_optional_string(_value), do: nil

  @spec maybe_expand_path(String.t() | nil) :: String.t() | nil
  def maybe_expand_path(nil), do: nil
  def maybe_expand_path(path) when is_binary(path), do: Path.expand(path)

  defp normalize_default_string(default, label) do
    case normalize_optional_string(default) do
      value when is_binary(value) -> {:ok, value}
      nil -> {:error, "Worker daemon #{label} is required."}
    end
  end
end
