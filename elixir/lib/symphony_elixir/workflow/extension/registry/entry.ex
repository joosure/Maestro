defmodule SymphonyElixir.Workflow.Extension.Registry.Entry do
  @moduledoc """
  Normalized workflow runtime-extension registration entry.

  The registry uses this struct as its stable internal model instead of passing
  raw modules around. Future plugin manifests can be normalized into the same
  entry shape without changing platform callers.
  """

  alias SymphonyElixir.Workflow.Extension
  alias SymphonyElixir.Workflow.Extension.{Diagnostics, ErrorCodes}
  alias SymphonyElixir.Workflow.Extension.Registry.Error

  @enforce_keys [:id, :module, :source]
  defstruct [:id, :module, :source]

  @id_pattern ~r/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/

  @type source :: :opts | :extra_opts | {:source, module()} | {:extra_source, module()}

  @type t :: %__MODULE__{
          id: String.t(),
          module: module(),
          source: source()
        }

  @type spec :: %{module: module(), source: source()}

  @spec normalize_many([spec()]) :: {:ok, [t()]} | {:error, map()}
  def normalize_many(specs) when is_list(specs) do
    specs
    |> Enum.reduce_while({:ok, []}, fn %{module: module, source: source}, {:ok, entries} ->
      case new(module, source) do
        {:ok, entry} -> {:cont, {:ok, [entry | entries]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec new(module(), source()) :: {:ok, t()} | {:error, map()}
  def new(module, source \\ :opts) do
    with {:ok, source} <- normalize_source(source),
         :ok <- validate_module_atom(module),
         :ok <- ensure_loaded(module),
         :ok <- ensure_callback(module, :id, 0, :extension_id_missing),
         :ok <- ensure_callback(module, :run_poll_cycle, 2, :extension_poll_cycle_missing),
         :ok <- ensure_behaviour(module),
         {:ok, id} <- extension_id(module) do
      {:ok, %__MODULE__{id: id, module: module, source: source}}
    else
      {:error, %{code: _code} = reason} -> {:error, reason}
    end
  end

  @spec new!(module(), source()) :: t()
  def new!(module, source \\ :opts) do
    case new(module, source) do
      {:ok, entry} -> entry
      {:error, reason} -> raise ArgumentError, Error.format(reason)
    end
  end

  @spec normalize_id(term()) :: {:ok, String.t()} | {:error, map()}
  def normalize_id(id) when is_binary(id) do
    normalized = String.trim(id)

    if Regex.match?(@id_pattern, normalized) do
      {:ok, normalized}
    else
      {:error, invalid_extension(nil, :extension_id_invalid, extension_id: id)}
    end
  end

  def normalize_id(id), do: {:error, invalid_extension(nil, :extension_id_invalid, extension_id: id)}

  @spec diagnostic(t()) :: map()
  def diagnostic(%__MODULE__{} = entry) do
    %{
      id: entry.id,
      module: inspect(entry.module),
      source: entry.source
    }
  end

  defp normalize_source(source) when source in [:opts, :extra_opts], do: {:ok, source}
  defp normalize_source({kind, module} = source) when kind in [:source, :extra_source] and is_atom(module) and not is_nil(module), do: {:ok, source}
  defp normalize_source(source), do: {:error, invalid_extension(nil, :extension_source_invalid, source: source)}

  defp validate_module_atom(module) when is_atom(module) and not is_nil(module), do: :ok
  defp validate_module_atom(module), do: {:error, invalid_extension(module, :invalid_extension_module)}

  defp ensure_loaded(module) do
    if Code.ensure_loaded?(module) do
      :ok
    else
      {:error, invalid_extension(module, :extension_not_loaded)}
    end
  end

  defp ensure_behaviour(module) do
    if implements_behaviour?(module, Extension) do
      :ok
    else
      {:error, invalid_extension(module, :extension_behaviour_missing)}
    end
  end

  defp ensure_callback(module, callback, arity, reason) do
    if function_exported?(module, callback, arity) do
      :ok
    else
      {:error, invalid_extension(module, reason)}
    end
  end

  defp extension_id(module) do
    case safe_call(module, :id, []) do
      {:ok, id} ->
        case normalize_id(id) do
          {:ok, normalized_id} ->
            {:ok, normalized_id}

          {:error, reason} ->
            {:error, %{reason | extension_module: inspect(module)}}
        end

      {:error, callback_error} ->
        {:error, invalid_extension(module, :extension_id_failed, callback_error: callback_error)}
    end
  end

  defp safe_call(module, callback, args) do
    {:ok, apply(module, callback, args)}
  rescue
    error ->
      {:error, Diagnostics.exception(error)}
  catch
    kind, reason ->
      {:error, Diagnostics.caught(kind, reason)}
  end

  defp implements_behaviour?(module, behaviour) do
    attributes = module.module_info(:attributes)

    behaviours =
      Keyword.get_values(attributes, :behaviour) ++
        Keyword.get_values(attributes, :behavior)

    behaviour in List.flatten(behaviours)
  end

  defp invalid_extension(module, reason, extra \\ []) do
    %{
      code: ErrorCodes.invalid_runtime_extension(),
      message: "Workflow runtime extension registration is invalid.",
      extension_module: inspect(module),
      reason: reason
    }
    |> Map.merge(Map.new(extra))
  end
end
