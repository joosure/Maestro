defmodule SymphonyElixir.Workflow.Extension.ToolResultRecorder.Registry do
  @moduledoc """
  Registry for workflow extension Dynamic Tool result recorders.

  The registry derives recorder modules from registered workflow extensions in
  the pre-plugin phase. Future plugin manifests can feed the same recorder
  entry boundary without changing tracker, repo, or repo-provider callers.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.ToolResultRecorder.Registry.{Collector, Error, Validator}
  alias SymphonyElixir.Workflow.Extension.ToolResultRecorder.Registry.Entry

  @type opts :: [
          entries: [module()],
          extra_entries: [module()],
          sources: [module()],
          extra_sources: [module()],
          source_opts: keyword(),
          recorder_modules: [module()],
          extra_recorder_modules: [module()]
        ]

  @spec entries(opts()) :: {:ok, [Entry.t()]} | {:error, map()}
  def entries(opts \\ []) do
    with {:ok, opts} <- normalize_opts(opts),
         {:ok, specs} <- Collector.recorder_specs(opts),
         :ok <- Validator.unique_modules(specs),
         {:ok, entries} <- Entry.normalize_many(specs),
         :ok <- Validator.unique_ids(entries) do
      {:ok, entries}
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
      {:error, Error.invalid(:tool_result_recorder_registry_opts_not_keyword, value_type: Diagnostics.type_name(opts))}
    end
  end

  defp normalize_opts(opts),
    do: {:error, Error.invalid(:tool_result_recorder_registry_opts_not_keyword, value_type: Diagnostics.type_name(opts))}
end
