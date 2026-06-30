defmodule SymphonyElixir.Storage.Scrubber do
  @moduledoc """
  Fail-closed storage scrubbing boundary for evidence-like payloads.

  Callers use this before handing payloads to durable storage or external
  rendering targets. Backend selection stays with `Storage.Redaction`; this
  module owns safe error shaping and type-preserving wrappers.
  """

  alias SymphonyElixir.Storage.ErrorCodes
  alias SymphonyElixir.Storage.Redaction

  @redaction_backend_opt :storage_redaction_backend
  @redaction_opts_key :storage_redaction_opts

  @spec scrub(term(), keyword()) :: {:ok, term()} | {:error, map()}
  def scrub(value, opts \\ []) when is_list(opts) do
    case Redaction.redact(value, redaction_opts(opts)) do
      {:error, reason} -> {:error, redaction_failed(reason)}
      redacted -> {:ok, redacted}
    end
  rescue
    error -> {:error, redaction_failed(%{reason: :backend_failed, exception: inspect(error.__struct__)})}
  catch
    kind, reason -> {:error, redaction_failed(%{reason: :backend_failed, kind: kind, reason_type: type_name(reason)})}
  end

  @spec scrub_map(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def scrub_map(value, opts \\ []) when is_map(value) and is_list(opts) do
    case scrub(value, opts) do
      {:ok, scrubbed} when is_map(scrubbed) ->
        {:ok, scrubbed}

      {:ok, scrubbed} ->
        {:error, redaction_failed(%{reason: :invalid_redaction_result, return_type: type_name(scrubbed)})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec scrub_map_list([map()], keyword()) :: {:ok, [map()]} | {:error, map()}
  def scrub_map_list(values, opts \\ []) when is_list(values) and is_list(opts) do
    case scrub(values, opts) do
      {:ok, scrubbed} when is_list(scrubbed) ->
        if Enum.all?(scrubbed, &is_map/1) do
          {:ok, scrubbed}
        else
          {:error, redaction_failed(%{reason: :invalid_redaction_result, return_type: "list"})}
        end

      {:ok, scrubbed} ->
        {:error, redaction_failed(%{reason: :invalid_redaction_result, return_type: type_name(scrubbed)})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp redaction_opts(opts) do
    opts
    |> Keyword.get(@redaction_opts_key, [])
    |> normalize_redaction_opts()
    |> put_backend(Keyword.get(opts, @redaction_backend_opt))
  end

  defp normalize_redaction_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: opts, else: []
  end

  defp normalize_redaction_opts(_opts), do: []

  defp put_backend(opts, nil), do: opts
  defp put_backend(opts, backend), do: Keyword.put(opts, :backend, backend)

  defp redaction_failed(reason) do
    %{
      code: ErrorCodes.redaction_failed(),
      message: "Payload could not be scrubbed before storage.",
      payload_summary: bounded_reason(reason)
    }
  end

  defp bounded_reason(reason) when is_map(reason) do
    Map.take(reason, [:code, :reason, :backend, :backend_type, :return_type, :exception, :kind, :reason_type])
  end

  defp bounded_reason(reason), do: %{reason_type: type_name(reason)}

  defp type_name(value) when is_binary(value), do: "string"
  defp type_name(value) when is_atom(value), do: "atom"
  defp type_name(value) when is_integer(value), do: "integer"
  defp type_name(value) when is_float(value), do: "float"
  defp type_name(value) when is_boolean(value), do: "boolean"
  defp type_name(value) when is_list(value), do: "list"
  defp type_name(value) when is_map(value), do: "map"
  defp type_name(value) when is_tuple(value), do: "tuple"
  defp type_name(_value), do: "term"
end
