defmodule SymphonyElixir.Workflow.Extension.StateStore.Config do
  @moduledoc """
  Application configuration boundary for workflow extension state storage.
  """

  alias SymphonyElixir.Workflow.Extension.StateStore.Error

  @app :symphony_elixir
  @config_key :workflow_extension_state_store
  @app_config_keys [:backend]

  @spec configured_backend() :: {:ok, module() | nil} | {:error, map()}
  def configured_backend do
    config = Application.get_env(@app, @config_key, [])

    cond do
      not is_list(config) or not Keyword.keyword?(config) ->
        {:error, Error.build(:configured_state_store_not_keyword, config)}

      unsupported_keys(config) != [] ->
        {:error, Error.build({:unsupported_config_keys, unsupported_keys(config)}, unsupported_keys(config))}

      true ->
        {:ok, Keyword.get(config, :backend)}
    end
  end

  defp unsupported_keys(config), do: config |> Keyword.keys() |> Enum.reject(&(&1 in @app_config_keys))
end
