defmodule SymphonyElixir.Workflow.Extension.OperatorCommand.Registry.Entry do
  @moduledoc """
  Normalized workflow extension operator-command registration entry.

  The registry uses this struct as its stable internal model so plugin
  manifests or built-in extensions can contribute commands without platform CLI
  code depending on concrete business modules.
  """

  alias SymphonyElixir.Workflow.Extension.{Diagnostics, ErrorCodes}
  alias SymphonyElixir.Workflow.Extension.OperatorCommand

  @enforce_keys [:id, :module, :source]
  defstruct [:id, :module, :source]

  @id_pattern ~r/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/

  @type source :: :opts | :extra_opts | {:extension, String.t(), module()}

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
         :ok <- ensure_callback(module, :id, 0, :command_id_missing),
         :ok <- ensure_callback(module, :evaluate, 2, :command_evaluate_missing),
         :ok <- ensure_behaviour(module),
         {:ok, id} <- command_id(module) do
      {:ok, %__MODULE__{id: id, module: module, source: source}}
    else
      {:error, %{code: _code} = reason} -> {:error, reason}
    end
  end

  @spec normalize_id(term()) :: {:ok, String.t()} | {:error, map()}
  def normalize_id(id) when is_binary(id) do
    normalized = String.trim(id)

    if Regex.match?(@id_pattern, normalized) do
      {:ok, normalized}
    else
      {:error, invalid_command(nil, :command_id_invalid, command_id: id)}
    end
  end

  def normalize_id(id), do: {:error, invalid_command(nil, :command_id_invalid, command_id: id)}

  @spec diagnostic(t()) :: map()
  def diagnostic(%__MODULE__{} = entry) do
    %{
      id: entry.id,
      module: inspect(entry.module),
      source: source_diagnostic(entry.source)
    }
  end

  defp normalize_source(source) when source in [:opts, :extra_opts], do: {:ok, source}

  defp normalize_source({:extension, extension_id, extension_module} = source)
       when is_binary(extension_id) and is_atom(extension_module) do
    {:ok, source}
  end

  defp normalize_source(source), do: {:error, invalid_command(nil, :command_source_invalid, source: source)}

  defp validate_module_atom(module) when is_atom(module) and not is_nil(module), do: :ok
  defp validate_module_atom(module), do: {:error, invalid_command(module, :invalid_command_module)}

  defp ensure_loaded(module) do
    if Code.ensure_loaded?(module) do
      :ok
    else
      {:error, invalid_command(module, :command_not_loaded)}
    end
  end

  defp ensure_callback(module, callback, arity, reason) do
    if function_exported?(module, callback, arity) do
      :ok
    else
      {:error, invalid_command(module, reason)}
    end
  end

  defp ensure_behaviour(module) do
    if implements_behaviour?(module, OperatorCommand) do
      :ok
    else
      {:error, invalid_command(module, :command_behaviour_missing)}
    end
  end

  defp command_id(module) do
    case safe_call(module, :id, []) do
      {:ok, id} ->
        case normalize_id(id) do
          {:ok, normalized_id} -> {:ok, normalized_id}
          {:error, reason} -> {:error, %{reason | command_module: inspect(module)}}
        end

      {:error, callback_error} ->
        {:error, invalid_command(module, :command_id_failed, callback_error: callback_error)}
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

  defp source_diagnostic({:extension, extension_id, extension_module}) do
    %{kind: :extension, extension_id: extension_id, extension_module: inspect(extension_module)}
  end

  defp source_diagnostic(source), do: source

  defp invalid_command(module, reason, extra \\ []) do
    %{
      code: ErrorCodes.invalid_operator_command(),
      message: "Workflow extension operator command registration is invalid.",
      command_module: inspect(module),
      reason: reason
    }
    |> Map.merge(Map.new(extra))
  end
end
