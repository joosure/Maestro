defmodule SymphonyElixir.RepoProvider.Query do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Error

  @spec run(term(), String.t(), String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def run(payload, expr, label \\ "repo-provider")
      when is_binary(expr) and is_binary(label) do
    with {:ok, tokens} <- parse(expr, label),
         {:ok, values, streamed?} <- evaluate([payload], tokens, false, expr, label) do
      {:ok, render(values, streamed?)}
    end
  end

  @spec parse(String.t(), String.t()) :: {:ok, [term()]} | {:error, Error.t()}
  def parse("." <> rest = expr, label) do
    parse_tokens(rest, [], label, expr)
  end

  def parse(expr, label) do
    {:error, unsupported_query(label, expr)}
  end

  defp parse_tokens("", acc, _label, _expr), do: {:ok, Enum.reverse(acc)}

  defp parse_tokens("[]" <> rest, acc, label, expr) do
    parse_tokens(rest, [:iter | acc], label, expr)
  end

  defp parse_tokens("[" <> rest, acc, label, expr) do
    case Regex.run(~r/^(\d+)\](.*)$/, rest, capture: :all_but_first) do
      [index, tail] ->
        parse_tokens(tail, [{:index, String.to_integer(index)} | acc], label, expr)

      _ ->
        {:error, unsupported_query(label, expr)}
    end
  end

  defp parse_tokens("." <> rest, acc, label, expr) do
    parse_field(rest, acc, label, expr)
  end

  defp parse_tokens(rest, acc, label, expr) do
    parse_field(rest, acc, label, expr)
  end

  defp parse_field(rest, acc, label, expr) do
    case Regex.run(~r/^([A-Za-z_][A-Za-z0-9_]*)(.*)$/, rest, capture: :all_but_first) do
      [field, tail] ->
        parse_tokens(tail, [{:field, field} | acc], label, expr)

      _ ->
        {:error, unsupported_query(label, expr)}
    end
  end

  defp evaluate(values, [], streamed?, _expr, _label), do: {:ok, values, streamed?}

  defp evaluate(values, [{:field, field} | rest], streamed?, expr, label) do
    next =
      Enum.map(values, fn
        %{} = value -> Map.get(value, field)
        nil -> nil
        _other -> throw({:error, unsupported_query(label, expr)})
      end)

    evaluate(next, rest, streamed?, expr, label)
  catch
    {:error, error} -> {:error, error}
  end

  defp evaluate(values, [{:index, index} | rest], streamed?, expr, label) do
    next =
      Enum.map(values, fn
        value when is_list(value) -> Enum.at(value, index)
        nil -> nil
        _other -> throw({:error, unsupported_query(label, expr)})
      end)

    evaluate(next, rest, streamed?, expr, label)
  catch
    {:error, error} -> {:error, error}
  end

  defp evaluate(values, [:iter | rest], _streamed?, expr, label) do
    next =
      Enum.flat_map(values, fn
        value when is_list(value) -> value
        nil -> []
        _other -> throw({:error, unsupported_query(label, expr)})
      end)

    evaluate(next, rest, true, expr, label)
  catch
    {:error, error} -> {:error, error}
  end

  defp render(values, true) do
    Enum.map_join(values, "", &render_one/1)
  end

  defp render([value | _rest], false), do: render_one(value)
  defp render([], false), do: "null\n"

  defp render_one(value) when is_binary(value), do: value <> "\n"
  defp render_one(value) when is_integer(value) or is_float(value), do: "#{value}\n"
  defp render_one(true), do: "true\n"
  defp render_one(false), do: "false\n"
  defp render_one(nil), do: "null\n"
  defp render_one(value), do: Jason.encode!(value) <> "\n"

  defp unsupported_query(label, expr) do
    Error.runtime_failure(
      :unsupported_query,
      "Unsupported #{label} jq expression: #{expr}"
    )
  end
end
