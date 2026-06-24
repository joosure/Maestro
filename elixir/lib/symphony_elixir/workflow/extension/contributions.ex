defmodule SymphonyElixir.Workflow.Extension.Contributions do
  @moduledoc """
  Aggregates optional contributions from registered workflow extensions.

  Platform contexts use this module as the assembly boundary for extension-owned
  profiles, templates, validators, runtime children, and evidence providers.
  The platform knows the contribution callback shape, not concrete extension
  modules or their business namespaces.
  """

  alias SymphonyElixir.Workflow.Extension.{Diagnostics, ErrorCodes}
  alias SymphonyElixir.Workflow.Extension.Registry

  @list_callbacks [
    :profiles,
    :template_entries,
    :completion_validators,
    :readiness_evidence_providers,
    :structured_execution_plan_evidence_binding_providers
  ]

  @spec list(atom(), keyword()) :: {:ok, [term()]} | {:error, map()}
  def list(callback, opts \\ []) when callback in @list_callbacks and is_list(opts) do
    with :ok <- validate_opts(opts),
         {:ok, modules} <- extension_modules(opts) do
      Enum.reduce_while(modules, {:ok, []}, fn module, {:ok, values} ->
        case list_from_extension(module, callback) do
          {:ok, contribution_values} -> {:cont, {:ok, values ++ contribution_values}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  @spec list!(atom(), keyword()) :: [term()]
  def list!(callback, opts \\ []) when callback in @list_callbacks and is_list(opts) do
    case list(callback, opts) do
      {:ok, values} -> values
      {:error, reason} -> raise ArgumentError, format_error(reason)
    end
  end

  @spec children(keyword()) :: {:ok, [Supervisor.child_spec()]} | {:error, map()}
  def children(opts \\ []) when is_list(opts) do
    with :ok <- validate_opts(opts),
         {:ok, modules} <- extension_modules(opts) do
      Enum.reduce_while(modules, {:ok, []}, fn module, {:ok, children} ->
        case children_from_extension(module, opts) do
          {:ok, extension_children} -> {:cont, {:ok, children ++ extension_children}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  @spec children!(keyword()) :: [Supervisor.child_spec()]
  def children!(opts \\ []) when is_list(opts) do
    case children(opts) do
      {:ok, children} -> children
      {:error, reason} -> raise ArgumentError, format_error(reason)
    end
  end

  defp extension_modules(opts) do
    case Registry.entries(registry_opts(opts)) do
      {:ok, entries} -> {:ok, Enum.map(entries, & &1.module)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp registry_opts(opts) do
    opts
    |> Keyword.take([:entries, :extra_entries, :sources, :extra_sources, :source_opts])
  end

  defp list_from_extension(module, callback) do
    if function_exported?(module, callback, 0) do
      case safe_apply(module, callback, []) do
        {:ok, values} when is_list(values) ->
          {:ok, values}

        {:ok, value} ->
          {:error, contribution_error(:contribution_not_list, module, callback, value_type: Diagnostics.type_name(value))}

        {:error, reason} ->
          {:error, contribution_error(:contribution_callback_failed, module, callback, callback_error: reason)}
      end
    else
      {:ok, []}
    end
  end

  defp children_from_extension(module, opts) do
    if function_exported?(module, :children, 1) do
      case safe_apply(module, :children, [opts]) do
        {:ok, children} when is_list(children) ->
          {:ok, children}

        {:ok, value} ->
          {:error, contribution_error(:children_not_list, module, :children, value_type: Diagnostics.type_name(value))}

        {:error, reason} ->
          {:error, contribution_error(:children_callback_failed, module, :children, callback_error: reason)}
      end
    else
      {:ok, []}
    end
  end

  defp safe_apply(module, callback, args) do
    {:ok, apply(module, callback, args)}
  rescue
    error -> {:error, Diagnostics.exception(error)}
  catch
    kind, reason -> {:error, Diagnostics.caught(kind, reason)}
  end

  defp validate_opts(opts) do
    if Keyword.keyword?(opts) do
      :ok
    else
      {:error,
       %{
         code: ErrorCodes.invalid_contribution(),
         message: "Workflow extension contribution options are invalid.",
         reason: :opts_not_keyword,
         value_type: Diagnostics.type_name(opts)
       }}
    end
  end

  defp contribution_error(reason, module, callback, extra) do
    %{
      code: ErrorCodes.invalid_contribution(),
      message: "Workflow extension contribution is invalid.",
      reason: reason,
      extension_module: inspect(module),
      callback: callback
    }
    |> Map.merge(Map.new(extra))
  end

  defp format_error(%{message: message, reason: reason, extension_module: module, callback: callback}) do
    "#{message} module=#{module} callback=#{callback} reason=#{format_reason(reason)}"
  end

  defp format_error(%{message: message, reason: reason}) do
    "#{message} reason=#{format_reason(reason)}"
  end

  defp format_error(reason), do: "Workflow extension contribution is invalid. reason_type=#{Diagnostics.type_name(reason)}"

  defp format_reason(reason) when is_atom(reason) and not is_nil(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: "type=#{Diagnostics.type_name(reason)}"
end
