defmodule SymphonyElixir.Workflow.Extension.Registry do
  @moduledoc """
  Trusted-source registry for workflow runtime extensions.

  Production application configuration registers source modules. Test and
  explicit assembly callers may still pass `entries:` opts, but root application
  configuration must not directly name concrete workflow business extensions.
  Future plugin manifests can feed this same source boundary without changing
  platform callers.
  """

  alias SymphonyElixir.Workflow.Extension.Registry.Collector
  alias SymphonyElixir.Workflow.Extension.Registry.Entry
  alias SymphonyElixir.Workflow.Extension.Registry.Error
  alias SymphonyElixir.Workflow.Extension.Registry.Validator

  @type opts :: [
          entries: [module()],
          extra_entries: [module()],
          sources: [module()],
          extra_sources: [module()],
          source_opts: keyword()
        ]

  @spec entries(opts()) :: {:ok, [Entry.t()]} | {:error, map()}
  def entries(opts \\ []) do
    with :ok <- Validator.validate_opts(opts),
         {:ok, specs} <- Collector.collect(opts),
         :ok <- Validator.validate_unique_modules(specs),
         {:ok, entries} <- Entry.normalize_many(specs),
         :ok <- Validator.validate_unique_ids(entries) do
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

  @spec validate!(opts()) :: :ok
  def validate!(opts \\ []) do
    case validate(opts) do
      :ok ->
        :ok

      {:error, reason} ->
        raise ArgumentError, Error.format(reason)
    end
  end
end
