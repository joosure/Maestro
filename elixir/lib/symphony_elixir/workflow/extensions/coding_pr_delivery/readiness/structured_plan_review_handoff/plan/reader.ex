defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.Plan.Reader do
  @moduledoc """
  Structured-plan reader port for review-handoff checks.

  The policy depends on this plugin-owned port instead of the platform store
  implementation. Bundled deployments use the host adapter
  `HostAdapters.Readiness.StructuredPlanReaderStoreBackend`; external plugin
  packages can provide another backend that implements this callback.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Readiness.StructuredPlanReaderStoreBackend, as: StoreBackend
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.Context

  @callback fetch_plan(Context.t(), term(), keyword()) :: {:ok, map()} | {:error, map()}

  @default_backend StoreBackend
  @reader_backend_opt :structured_plan_reader_backend
  @reader_opts_key :structured_plan_reader_opts
  @server_key :server
  @store_unavailable_code "store_unavailable"
  @invalid_backend_reason "structured_plan_reader_backend_invalid"
  @backend_failed_reason "structured_plan_reader_backend_failed"

  @spec fetch(Context.t(), term(), keyword()) :: {:ok, map()} | {:error, map()}
  def fetch(context, config, opts) when is_map(context) and is_list(opts) do
    with :ok <- validate_opts(opts),
         {:ok, backend} <- backend(config, opts),
         {:ok, reader_opts} <- reader_opts(config, opts) do
      call_backend(backend, context, config, reader_opts)
    end
  end

  def fetch(_context, _config, opts) do
    {:error, unavailable(@invalid_backend_reason, %{value_type: Diagnostics.type_name(opts)})}
  end

  defp validate_opts(opts) do
    if Keyword.keyword?(opts) do
      :ok
    else
      {:error, unavailable(@invalid_backend_reason, %{value_type: "non_keyword_list"})}
    end
  end

  defp backend(config, opts) do
    backend = Context.option_value(config, :reader_backend) || Keyword.get(opts, @reader_backend_opt) || @default_backend

    cond do
      not is_atom(backend) ->
        {:error, unavailable(@invalid_backend_reason, %{backend_type: Diagnostics.type_name(backend)})}

      not Code.ensure_loaded?(backend) ->
        {:error, unavailable(@invalid_backend_reason, %{backend_type: "module_not_loaded"})}

      not function_exported?(backend, :fetch_plan, 3) ->
        {:error, unavailable(@invalid_backend_reason, %{backend_type: "missing_fetch_plan_callback"})}

      true ->
        {:ok, backend}
    end
  end

  defp reader_opts(config, opts) do
    (Context.option_value(config, :reader_opts) || Keyword.get(opts, @reader_opts_key))
    |> normalize_reader_opts()
    |> case do
      {:ok, reader_opts} ->
        server =
          Context.option_value(config, @server_key) ||
            Keyword.get(reader_opts, @server_key)

        {:ok, maybe_put(reader_opts, @server_key, server)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_reader_opts(nil), do: {:ok, []}

  defp normalize_reader_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, opts}
    else
      {:error, unavailable(@invalid_backend_reason, %{reader_opts_type: "non_keyword_list"})}
    end
  end

  defp normalize_reader_opts(opts) do
    {:error, unavailable(@invalid_backend_reason, %{reader_opts_type: Diagnostics.type_name(opts)})}
  end

  defp call_backend(backend, context, config, reader_opts) do
    backend.fetch_plan(context, config, reader_opts)
  rescue
    error -> {:error, unavailable(@backend_failed_reason, Diagnostics.exception(error))}
  catch
    kind, reason -> {:error, unavailable(@backend_failed_reason, Diagnostics.caught(kind, reason))}
  end

  defp unavailable(reason, metadata) do
    %{code: @store_unavailable_code, reason: reason}
    |> Map.merge(metadata)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
