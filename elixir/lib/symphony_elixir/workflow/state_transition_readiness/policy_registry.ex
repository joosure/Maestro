defmodule SymphonyElixir.Workflow.StateTransitionReadiness.PolicyRegistry do
  @moduledoc """
  Registry of readiness policy integrations contributed by workflow extensions.

  Platform readiness owns the registry boundary and contract validation; concrete
  workflow extensions own policy modules and evidence-recorder modules.
  """

  alias SymphonyElixir.Workflow.Extension.Registry, as: ExtensionRegistry
  alias SymphonyElixir.Workflow.StateTransitionReadiness.EvidenceRecorder.Behaviour, as: EvidenceRecorderBehaviour
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Policy, as: ReadinessPolicy

  @type opts :: [
          entries: [module()],
          extra_entries: [module()],
          sources: [module()],
          extra_sources: [module()],
          source_opts: keyword(),
          policy_modules: [module()],
          extra_policy_modules: [module()],
          evidence_recorder_modules: [module()],
          extra_evidence_recorder_modules: [module()]
        ]

  @spec policies() :: [module()]
  @spec policies(opts()) :: [module()]
  def policies(opts \\ []) do
    opts
    |> modules(:readiness_policies, :policy_modules, :extra_policy_modules, &validate_policy_module/2)
    |> unwrap!()
  end

  @spec evidence_recorders() :: [module()]
  @spec evidence_recorders(opts()) :: [module()]
  def evidence_recorders(opts \\ []) do
    opts
    |> modules(
      :readiness_evidence_recorders,
      :evidence_recorder_modules,
      :extra_evidence_recorder_modules,
      &validate_evidence_recorder_module/2
    )
    |> unwrap!()
  end

  @spec validate() :: :ok | {:error, map()}
  @spec validate(opts()) :: :ok | {:error, map()}
  def validate(opts \\ []) do
    with {:ok, _policies} <-
           modules(opts, :readiness_policies, :policy_modules, :extra_policy_modules, &validate_policy_module/2),
         {:ok, _recorders} <-
           modules(
             opts,
             :readiness_evidence_recorders,
             :evidence_recorder_modules,
             :extra_evidence_recorder_modules,
             &validate_evidence_recorder_module/2
           ) do
      :ok
    end
  end

  @spec validate!() :: :ok
  @spec validate!(opts()) :: :ok
  def validate!(opts \\ []) do
    case validate(opts) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, format_error(reason)
    end
  end

  defp modules(opts, callback, override_key, extra_key, validator) do
    with {:ok, base_specs} <- base_specs(opts, callback, override_key),
         extra_specs <- opts |> Keyword.get(extra_key, []) |> sourced_modules(:extra_opts),
         specs <- Enum.uniq_by(base_specs ++ extra_specs, & &1.module) do
      normalize_modules(specs, validator)
    end
  end

  defp base_specs(opts, callback, override_key) do
    if Keyword.has_key?(opts, override_key) do
      {:ok, opts |> Keyword.get(override_key, []) |> sourced_modules(:opts)}
    else
      extension_contribution_specs(opts, callback)
    end
  end

  defp extension_contribution_specs(opts, callback) do
    opts
    |> extension_registry_opts()
    |> ExtensionRegistry.entries()
    |> case do
      {:ok, extension_entries} -> collect_extension_specs(extension_entries, callback)
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect_extension_specs(extension_entries, callback) do
    Enum.reduce_while(extension_entries, {:ok, []}, fn extension_entry, {:ok, specs} ->
      case modules_from_extension(extension_entry, callback) do
        {:ok, modules} ->
          source = {:extension, extension_entry.id, extension_entry.module}
          {:cont, {:ok, specs ++ sourced_modules(modules, source)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp modules_from_extension(extension_entry, callback) do
    module = extension_entry.module

    if function_exported?(module, callback, 0) do
      case safe_call(module, callback, []) do
        {:ok, modules} when is_list(modules) ->
          {:ok, modules}

        {:ok, modules} ->
          {:error,
           invalid_registry(:extension_callback_not_list,
             extension_id: extension_entry.id,
             extension_module: inspect(module),
             callback: callback,
             value_type: diagnostic_type(modules)
           )}

        {:error, callback_error} ->
          {:error,
           invalid_registry(:extension_callback_failed,
             extension_id: extension_entry.id,
             extension_module: inspect(module),
             callback: callback,
             callback_error: callback_error
           )}
      end
    else
      {:ok, []}
    end
  end

  defp sourced_modules(modules, source) do
    modules
    |> List.wrap()
    |> Enum.map(&%{module: &1, source: source})
  end

  defp normalize_modules(specs, validator) do
    Enum.reduce_while(specs, {:ok, []}, fn %{module: module, source: source}, {:ok, modules} ->
      case validator.(module, source) do
        :ok -> {:cont, {:ok, [module | modules]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, modules} -> {:ok, Enum.reverse(modules)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_policy_module(module, source) do
    with :ok <- validate_module_atom(module, source),
         :ok <- ensure_loaded(module, source),
         :ok <- ensure_behaviour(module, ReadinessPolicy, source, :readiness_policy_behaviour_missing),
         :ok <- ensure_callback(module, :policy_id, 0, source),
         :ok <- ensure_callback(module, :schema, 0, source),
         :ok <- ensure_callback(module, :governed_target?, 2, source),
         :ok <- ensure_callback(module, :validate, 3, source) do
      :ok
    end
  end

  defp validate_evidence_recorder_module(module, source) do
    with :ok <- validate_module_atom(module, source),
         :ok <- ensure_loaded(module, source),
         :ok <- ensure_behaviour(module, EvidenceRecorderBehaviour, source, :evidence_recorder_behaviour_missing),
         :ok <- ensure_callback(module, :record_typed_tool_result, 6, source) do
      :ok
    end
  end

  defp validate_module_atom(module, _source) when is_atom(module) and not is_nil(module), do: :ok

  defp validate_module_atom(module, source),
    do: {:error, invalid_registry(:invalid_module, module: inspect(module), source: inspect(source))}

  defp ensure_loaded(module, source) do
    if Code.ensure_loaded?(module) do
      :ok
    else
      {:error, invalid_registry(:module_not_loaded, module: inspect(module), source: inspect(source))}
    end
  end

  defp ensure_behaviour(module, behaviour, source, reason) do
    if implements_behaviour?(module, behaviour) do
      :ok
    else
      {:error, invalid_registry(reason, module: inspect(module), source: inspect(source), behaviour: inspect(behaviour))}
    end
  end

  defp ensure_callback(module, callback, arity, source) do
    if function_exported?(module, callback, arity) do
      :ok
    else
      {:error,
       invalid_registry(:callback_missing,
         module: inspect(module),
         source: inspect(source),
         callback: "#{callback}/#{arity}"
       )}
    end
  end

  defp extension_registry_opts(opts) do
    opts
    |> Keyword.take([:entries, :extra_entries, :sources, :extra_sources, :source_opts])
    |> case do
      [] -> []
      registry_opts -> registry_opts
    end
  end

  defp safe_call(module, callback, args) do
    {:ok, apply(module, callback, args)}
  rescue
    error ->
      {:error, %{kind: :error, error: Exception.message(error)}}
  catch
    kind, reason ->
      {:error, %{kind: kind, reason: inspect(reason)}}
  end

  defp implements_behaviour?(module, behaviour) do
    attributes = module.module_info(:attributes)

    behaviours =
      Keyword.get_values(attributes, :behaviour) ++
        Keyword.get_values(attributes, :behavior)

    behaviour in List.flatten(behaviours)
  end

  defp unwrap!({:ok, modules}), do: modules

  defp unwrap!({:error, reason}) do
    raise ArgumentError, format_error(reason)
  end

  defp format_error(reason), do: "Invalid state-transition readiness registry: #{inspect(reason)}"

  defp invalid_registry(reason, extra) do
    %{
      code: "invalid_state_transition_readiness_registry",
      message: "State-transition readiness registry is invalid.",
      reason: reason
    }
    |> Map.merge(Map.new(extra))
  end

  defp diagnostic_type(value) when is_atom(value) and not is_nil(value), do: "atom"
  defp diagnostic_type(value) when is_binary(value), do: "string"
  defp diagnostic_type(value) when is_boolean(value), do: "boolean"
  defp diagnostic_type(value) when is_integer(value), do: "integer"
  defp diagnostic_type(value) when is_float(value), do: "float"
  defp diagnostic_type(value) when is_list(value), do: "list"
  defp diagnostic_type(value) when is_map(value), do: "map"
  defp diagnostic_type(nil), do: "nil"
  defp diagnostic_type(_value), do: "term"
end
