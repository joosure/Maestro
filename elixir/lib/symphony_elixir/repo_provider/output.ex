defmodule SymphonyElixir.RepoProvider.Output do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Query
  alias SymphonyElixir.RepoProvider.Result

  @type rendered :: %{
          stdout: String.t(),
          stderr: String.t(),
          exit_code: non_neg_integer(),
          error: Error.t() | nil
        }

  @spec render(Result.t()) :: {String.t(), String.t(), non_neg_integer()}
  def render(%Result{} = result) do
    result
    |> render_with_diagnostics()
    |> to_tuple()
  end

  @spec render_with_diagnostics(Result.t()) :: rendered()
  def render_with_diagnostics(%Result{mode: :text, payload: payload, exit_code: exit_code})
      when is_binary(payload) do
    %{
      stdout: ensure_newline(payload),
      stderr: "",
      exit_code: exit_code,
      error: nil
    }
  end

  def render_with_diagnostics(%Result{
        mode: :json,
        payload: payload,
        json_fields: json_fields,
        jq: jq,
        query_label: query_label,
        exit_code: exit_code
      }) do
    selected = select_fields(payload, json_fields)

    if is_binary(jq) do
      case Query.run(selected, jq, query_label) do
        {:ok, query_output} ->
          %{
            stdout: query_output,
            stderr: "",
            exit_code: exit_code,
            error: nil
          }

        {:error, %Error{} = error} ->
          %{
            stdout: "",
            stderr: ensure_newline(error.message),
            exit_code: error.exit_code,
            error: error
          }
      end
    else
      %{
        stdout: ensure_newline(Jason.encode!(selected)),
        stderr: "",
        exit_code: exit_code,
        error: nil
      }
    end
  end

  @spec render_error(Error.t()) :: {String.t(), String.t(), non_neg_integer()}
  def render_error(%Error{} = error) do
    error
    |> render_error_with_diagnostics()
    |> to_tuple()
  end

  @spec render_error_with_diagnostics(Error.t()) :: rendered()
  def render_error_with_diagnostics(%Error{} = error) do
    %{
      stdout: "",
      stderr: ensure_newline(error.message),
      exit_code: error.exit_code,
      error: error
    }
  end

  @spec select_fields(term(), nil | [String.t()]) :: term()
  def select_fields(payload, nil), do: payload
  def select_fields(payload, []), do: payload

  def select_fields(payload, fields) when is_map(payload) and is_list(fields) do
    Map.take(payload, fields)
  end

  def select_fields(payload, fields) when is_list(payload) and is_list(fields) do
    Enum.map(payload, &select_fields(&1, fields))
  end

  def select_fields(payload, _fields), do: payload

  defp ensure_newline(text) when is_binary(text) do
    if String.ends_with?(text, "\n"), do: text, else: text <> "\n"
  end

  defp to_tuple(%{stdout: stdout, stderr: stderr, exit_code: exit_code}) do
    {stdout, stderr, exit_code}
  end
end
