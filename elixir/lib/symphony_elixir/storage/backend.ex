defmodule SymphonyElixir.Storage.Backend do
  @moduledoc """
  Shared validation helpers for storage infrastructure backends.

  Storage facades use this module to fail with stable machine-readable errors
  before calling configured backend modules.
  """

  alias SymphonyElixir.Storage.ErrorCodes

  @type validation_error :: {:error, map()}

  @spec validate(module(), module(), atom(), non_neg_integer()) :: :ok | validation_error()
  def validate(module, behaviour, callback, arity)
      when is_atom(behaviour) and is_atom(callback) and is_integer(arity) and arity >= 0 do
    cond do
      not is_atom(module) or is_nil(module) ->
        unsupported(module, :invalid_backend_module)

      not Code.ensure_loaded?(module) ->
        unsupported(module, :backend_not_loaded)

      not function_exported?(module, callback, arity) ->
        unsupported(module, :backend_callback_missing)

      not implements_behaviour?(module, behaviour) ->
        unsupported(module, :backend_behaviour_missing)

      true ->
        :ok
    end
  end

  defp implements_behaviour?(module, behaviour) do
    module
    |> module_behaviours()
    |> Enum.member?(behaviour)
  end

  defp module_behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.take([:behaviour, :behavior])
    |> Keyword.values()
    |> List.flatten()
  end

  defp unsupported(module, reason) do
    {:error,
     %{
       code: ErrorCodes.unsupported_backend(),
       message: "Storage backend is not supported.",
       backend: inspect(module),
       reason: reason
     }}
  end
end
