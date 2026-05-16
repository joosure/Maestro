defmodule SymphonyElixir.Tracker.Error do
  @moduledoc """
  Normalized tracker error struct and conversion helpers.

  All adapter failures — whether HTTP errors, missing credentials, or
  domain-level rejections — should be wrapped in `%Error{}` before
  crossing the adapter boundary. The struct carries:

    * `provider` — adapter kind that produced the error
    * `operation` — logical operation (e.g. `:fetch_candidate_issues`)
    * `code` — semantic error code (`:missing_credentials`, `:not_found`, …)
    * `message` — human-readable description
    * `retryable?` — whether the orchestrator should schedule a retry
    * `details` — opaque map with provider-specific diagnostics

  ## Normalization

  Use `normalize/3` to convert raw error reasons (atoms, tuples, strings)
  into `%Error{}`. The normalizer applies generic patterns first, then
  uses `:unknown`. Provider-specific patterns should live inside
  each adapter's own error constructors.
  """

  @enforce_keys [:provider, :operation, :code]
  defstruct [:provider, :operation, :code, :message, retryable?: false, details: %{}]

  @type t :: %__MODULE__{
          provider: String.t(),
          operation: atom() | String.t(),
          code: atom() | String.t(),
          message: String.t() | nil,
          retryable?: boolean(),
          details: map()
        }

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    provider = Map.fetch!(attrs, :provider)
    operation = Map.fetch!(attrs, :operation)
    code = Map.fetch!(attrs, :code)

    struct(__MODULE__, %{
      provider: to_provider(provider),
      operation: operation,
      code: code,
      message: Map.get(attrs, :message),
      retryable?: Map.get(attrs, :retryable?, false),
      details: Map.get(attrs, :details, %{})
    })
  end

  @spec normalize(map() | String.t() | nil, atom() | String.t(), term()) :: t()
  def normalize(provider_or_tracker, operation, {:error, reason}) do
    normalize(provider_or_tracker, operation, reason)
  end

  def normalize(provider_or_tracker, operation, %__MODULE__{} = error) do
    provider = to_provider(provider_or_tracker)

    %__MODULE__{
      error
      | provider: if(error.provider in [nil, "", "unknown"], do: provider, else: error.provider),
        operation: if(is_nil(error.operation), do: operation, else: error.operation)
    }
  end

  def normalize(provider_or_tracker, operation, reason) do
    provider = to_provider(provider_or_tracker)
    do_normalize(provider, operation, reason)
  end

  @spec retryable?(t() | term()) :: boolean()
  def retryable?(%__MODULE__{retryable?: retryable?}), do: retryable? == true
  def retryable?(reason), do: normalize("unknown", :unknown, reason).retryable?

  defp do_normalize(provider, operation, {:unsupported_tracker_kind, kind}) do
    error(provider, operation, :unsupported_provider,
      message: "Tracker kind #{inspect(kind)} is not supported.",
      details: %{kind: kind, source_reason: {:unsupported_tracker_kind, kind}}
    )
  end

  defp do_normalize(provider, operation, :unsupported_tracker_read_capability) do
    error(provider, operation, :unsupported_capability,
      message: "Tracker provider does not support read operations.",
      details: %{capability: :reader, source_reason: :unsupported_tracker_read_capability}
    )
  end

  defp do_normalize(provider, operation, :unsupported_tracker_write_capability) do
    error(provider, operation, :unsupported_capability,
      message: "Tracker provider does not support write operations.",
      details: %{capability: :writer, source_reason: :unsupported_tracker_write_capability}
    )
  end

  defp do_normalize(provider, operation, :state_not_found) do
    error(provider, operation, :not_found,
      message: "Requested tracker state was not found.",
      details: %{source_reason: :state_not_found}
    )
  end

  defp do_normalize(provider, operation, {:state_conflict, details}) when is_map(details) do
    error(provider, operation, :state_conflict,
      message: "Tracker issue state changed before conditional state update.",
      details: Map.put(details, :source_reason, {:state_conflict, details})
    )
  end

  defp do_normalize(provider, operation, reason)
       when reason in [:comment_create_failed, :issue_update_failed] do
    error(provider, operation, :write_failed,
      message: "Tracker write operation did not complete successfully.",
      details: %{source_reason: reason}
    )
  end

  defp do_normalize(provider, operation, reason) do
    error(provider, operation, :unknown,
      message: "Tracker operation failed.",
      details: %{source_reason: reason}
    )
  end

  defp error(provider, operation, code, opts) do
    new(%{
      provider: provider,
      operation: operation,
      code: code,
      message: Keyword.get(opts, :message),
      retryable?: Keyword.get(opts, :retryable?, false),
      details: Keyword.get(opts, :details, %{})
    })
  end

  defp to_provider(%{kind: kind}) when is_binary(kind), do: kind
  defp to_provider(provider) when is_binary(provider) and provider != "", do: provider
  defp to_provider(provider) when is_atom(provider), do: Atom.to_string(provider)
  defp to_provider(_provider), do: "unknown"
end
