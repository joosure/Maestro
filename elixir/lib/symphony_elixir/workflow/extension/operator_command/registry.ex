defmodule SymphonyElixir.Workflow.Extension.OperatorCommand.Registry do
  @moduledoc """
  Registry for workflow extension operator commands.

  The registry derives command modules from registered workflow extensions in
  the pre-plugin phase and exposes only command-list, lookup, and validation
  facade functions. Future trusted registration projections can feed the same
  command-entry boundary without changing this public surface.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.OperatorCommand.Registry.{Collector, Error, Validator}
  alias SymphonyElixir.Workflow.Extension.OperatorCommand.Registry.Entry

  @type opts :: [
          entries: [module()],
          extra_entries: [module()],
          sources: [module()],
          extra_sources: [module()],
          source_opts: keyword(),
          command_modules: [module()],
          extra_command_modules: [module()]
        ]

  @spec entries(opts()) :: {:ok, [Entry.t()]} | {:error, map()}
  def entries(opts \\ []) do
    with {:ok, opts} <- normalize_opts(opts),
         {:ok, specs} <- Collector.command_specs(opts),
         :ok <- Validator.unique_modules(specs),
         {:ok, entries} <- Entry.normalize_many(specs),
         :ok <- Validator.unique_ids(entries) do
      {:ok, entries}
    end
  end

  @spec fetch(String.t(), opts()) :: {:ok, Entry.t()} | {:error, map()}
  def fetch(command_id, opts \\ []) do
    with {:ok, normalized_id} <- Entry.normalize_id(command_id),
         {:ok, entries} <- entries(opts) do
      case Enum.find(entries, &(&1.id == normalized_id)) do
        nil -> {:error, Error.not_found(normalized_id, entries)}
        entry -> {:ok, entry}
      end
    end
  end

  @spec validate(opts()) :: :ok | {:error, map()}
  def validate(opts \\ []) do
    case entries(opts) do
      {:ok, _entries} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, opts}
    else
      {:error, Error.invalid(:operator_command_registry_opts_not_keyword, value_type: Diagnostics.type_name(opts))}
    end
  end

  defp normalize_opts(opts),
    do: {:error, Error.invalid(:operator_command_registry_opts_not_keyword, value_type: Diagnostics.type_name(opts))}
end
