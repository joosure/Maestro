defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry.Options do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry.Error
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage, as: KnownTargetStorage

  @default_max_targets 10_000

  @spec validate(term()) :: {:ok, keyword()} | {:error, map()}
  def validate(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: {:ok, opts}, else: {:error, Error.invalid_options(opts)}
  end

  def validate(opts), do: {:error, Error.invalid_options(opts)}

  @spec validate_attrs(term()) :: :ok | {:error, map()}
  def validate_attrs(attrs) when is_map(attrs), do: :ok
  def validate_attrs(attrs), do: {:error, Error.invalid_attrs(attrs)}

  @spec validate_issue_id(term()) :: :ok | {:error, map()}
  def validate_issue_id(issue_id) when is_binary(issue_id), do: :ok
  def validate_issue_id(issue_id), do: {:error, Error.invalid_issue_id(issue_id)}

  @spec max_targets(keyword()) :: pos_integer()
  def max_targets(opts), do: positive_integer(Keyword.get(opts, :max_targets), @default_max_targets)

  @spec target_ttl_ms(keyword()) :: non_neg_integer() | nil
  def target_ttl_ms(opts), do: non_negative_integer_or_nil(Keyword.get(opts, :target_ttl_ms))

  @spec storage_opts(term()) :: {:ok, keyword() | nil} | {:error, map()}
  def storage_opts(opts) when is_list(opts) do
    with {:ok, backend} <- storage_backend(opts) do
      {:ok, build_storage_opts(opts, backend)}
    end
  end

  def storage_opts(opts), do: {:error, Error.invalid_options(opts)}

  @spec normalize_attrs(map()) :: map()
  def normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {known_atom_key(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp storage_backend(opts) do
    case Keyword.get(opts, :storage_backend, :default) do
      false -> {:ok, nil}
      nil -> {:ok, nil}
      :default -> {:ok, default_storage_backend(opts)}
      backend when is_atom(backend) -> {:ok, backend}
      backend -> {:error, Error.invalid_storage_backend(backend)}
    end
  end

  defp default_storage_backend(opts) do
    case Keyword.get(opts, :workflow_scope) do
      scope when is_map(scope) -> KnownTargetStorage.default_backend()
      _scope -> nil
    end
  end

  defp build_storage_opts(_opts, nil), do: nil

  defp build_storage_opts(opts, backend) do
    [
      backend: backend,
      workflow_scope: Keyword.get(opts, :workflow_scope)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp known_atom_key(:issue_id), do: Fields.issue_id()
  defp known_atom_key(:tracker_kind), do: Fields.tracker_kind()
  defp known_atom_key(:repo_provider_kind), do: Fields.repo_provider_kind()
  defp known_atom_key(:repository), do: Fields.repository()
  defp known_atom_key(:number), do: Fields.number()
  defp known_atom_key(:change_proposal_id), do: Fields.change_proposal_id()
  defp known_atom_key(:url), do: Fields.url()
  defp known_atom_key(:branch), do: Fields.branch()
  defp known_atom_key(:head_sha), do: Fields.head_sha()
  defp known_atom_key(:last_observed_signature), do: Fields.last_observed_signature()
  defp known_atom_key(:last_observed_at), do: Fields.last_observed_at()
  defp known_atom_key(:last_enqueued_at_ms), do: Fields.last_enqueued_at_ms()
  defp known_atom_key(:registered_at_ms), do: Fields.registered_at_ms()
  defp known_atom_key(:updated_at_ms), do: Fields.updated_at_ms()
  defp known_atom_key(key), do: key

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp non_negative_integer_or_nil(value) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer_or_nil(_value), do: nil
end
