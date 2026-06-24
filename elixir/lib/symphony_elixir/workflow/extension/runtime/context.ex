defmodule SymphonyElixir.Workflow.Extension.Runtime.Context do
  @moduledoc """
  Stable runtime input envelope passed to workflow extensions.

  The context keeps extension callbacks independent from the Orchestrator's
  internal state map. Extensions receive stable runtime facts, a workflow scope,
  and platform metadata.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.ErrorCodes
  alias SymphonyElixir.Workflow.Extension.Runtime.Projection, as: RuntimeProjection
  alias SymphonyElixir.Workflow.Extension.Runtime.Scope, as: RuntimeScope

  @enforce_keys [:settings, :runtime, :workflow_scope]
  defstruct [:settings, :runtime, :workflow_scope, metadata: %{}]

  @type t :: %__MODULE__{
          settings: map(),
          runtime: RuntimeProjection.t(),
          workflow_scope: map(),
          metadata: map()
        }

  @spec new(term(), term(), term()) :: {:ok, t()} | {:error, map()}
  def new(settings, runtime_state, opts \\ [])

  def new(settings, runtime_state, opts) when is_map(settings) and is_map(runtime_state) and is_list(opts) do
    with :ok <- validate_opts(opts),
         {:ok, metadata} <- metadata(opts),
         {:ok, workflow_scope} <- RuntimeScope.new(settings, opts) do
      {:ok,
       %__MODULE__{
         settings: settings,
         runtime: RuntimeProjection.new(runtime_state),
         workflow_scope: workflow_scope,
         metadata: metadata
       }}
    end
  end

  def new(settings, _runtime_state, _opts) when not is_map(settings) do
    {:error, error(:settings_not_map, value_type: Diagnostics.type_name(settings))}
  end

  def new(_settings, runtime_state, _opts) when not is_map(runtime_state) do
    {:error, error(:runtime_state_not_map, value_type: Diagnostics.type_name(runtime_state))}
  end

  def new(_settings, _runtime_state, opts) do
    {:error, error(:opts_not_keyword, value_type: Diagnostics.type_name(opts))}
  end

  @spec new!(term(), term(), term()) :: t()
  def new!(settings, runtime_state, opts \\ []) do
    case new(settings, runtime_state, opts) do
      {:ok, context} -> context
      {:error, reason} -> raise ArgumentError, format_error(reason)
    end
  end

  @spec refresh_runtime(t(), map()) :: t()
  def refresh_runtime(%__MODULE__{} = context, runtime_state) when is_map(runtime_state) do
    %{context | runtime: RuntimeProjection.new(runtime_state)}
  end

  defp validate_opts(opts) do
    if Keyword.keyword?(opts) do
      :ok
    else
      {:error, error(:opts_not_keyword, value_type: Diagnostics.type_name(opts))}
    end
  end

  defp metadata(opts) do
    if Keyword.has_key?(opts, :metadata) do
      opts
      |> Keyword.fetch!(:metadata)
      |> normalize_metadata()
    else
      {:ok, %{}}
    end
  end

  defp normalize_metadata(metadata) when is_map(metadata), do: {:ok, metadata}
  defp normalize_metadata(metadata), do: {:error, error(:metadata_not_map, value_type: Diagnostics.type_name(metadata))}

  defp error(reason, fields) do
    %{
      code: ErrorCodes.invalid_runtime_context(),
      message: "Workflow extension runtime context is invalid.",
      reason: reason
    }
    |> Map.merge(Map.new(fields))
  end

  defp format_error(reason) when is_map(reason) do
    reason_text =
      reason
      |> Map.get(:reason)
      |> format_reason()

    value_type = Map.get(reason, :value_type, "unknown")

    "invalid workflow extension runtime context: reason=#{reason_text} value_type=#{value_type}"
  end

  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(_reason), do: "invalid"
end
