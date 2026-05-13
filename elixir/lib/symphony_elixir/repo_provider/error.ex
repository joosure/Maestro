defmodule SymphonyElixir.RepoProvider.Error do
  @moduledoc """
  Structured error type for the repo-provider subsystem.

  Provides a uniform error representation across all adapters with
  support for exit codes, operation tagging, and retryability hints.

  ## Fields

    * `:code` — machine-readable error identifier (atom)
    * `:message` — human-readable description
    * `:details` — arbitrary term with context (payload, exception…)
    * `:exit_code` — process exit code (64 = usage, 1 = runtime)
    * `:provider` — adapter kind that produced the error (e.g. `"cnb"`)
    * `:operation` — logical operation that failed (e.g. `:pr_view`)
    * `:retryable?` — hint for callers about transient failures
  """

  alias SymphonyElixir.RepoProvider.Config, as: RepoConfig

  defstruct [:code, :message, :details, :provider, :operation, exit_code: 1, retryable?: false]

  @type t :: %__MODULE__{
          code: atom(),
          message: String.t(),
          details: term(),
          exit_code: non_neg_integer(),
          provider: String.t() | nil,
          operation: atom() | nil,
          retryable?: boolean()
        }

  @spec invalid_invocation(String.t()) :: t()
  def invalid_invocation(message) when is_binary(message) do
    %__MODULE__{
      code: :invalid_invocation,
      message: message,
      details: nil,
      exit_code: 64
    }
  end

  @spec unsupported_provider(String.t() | nil) :: t()
  def unsupported_provider(kind) do
    %__MODULE__{
      code: :unsupported_provider,
      message: "Unsupported repo provider: #{kind}",
      details: kind,
      provider: kind,
      exit_code: 64
    }
  end

  @spec unsupported_option(String.t() | nil, atom()) :: t()
  def unsupported_option(kind, option) when is_atom(option) do
    %__MODULE__{
      code: :unsupported_option,
      message: unsupported_option_message(kind, option),
      details: %{provider: kind, option: option, source_reason: {:unsupported_repo_provider_option, kind, option}},
      provider: kind,
      operation: :validate_config,
      exit_code: 64
    }
  end

  @spec invalid_option(String.t() | nil, atom(), String.t()) :: t()
  def invalid_option(kind, option, message) when is_atom(option) and is_binary(message) do
    %__MODULE__{
      code: :invalid_option,
      message: message,
      details: %{provider: kind, option: option},
      provider: kind,
      operation: :validate_config,
      exit_code: 64
    }
  end

  @spec unsupported_capability(String.t() | nil, atom()) :: t()
  def unsupported_capability(kind, operation) when is_atom(operation) do
    %__MODULE__{
      code: :unsupported_capability,
      message: "Repo provider #{kind || "unknown"} does not support #{operation}",
      details: %{provider: kind, operation: operation},
      provider: kind,
      operation: operation,
      exit_code: 64
    }
  end

  @spec missing_tooling(String.t(), String.t()) :: t()
  def missing_tooling(tool, provider) when is_binary(tool) and is_binary(provider) do
    %__MODULE__{
      code: :missing_tooling,
      message: "#{provider} provider requires #{tool} in PATH",
      details: %{tool: tool, provider: provider},
      provider: provider,
      exit_code: 64
    }
  end

  @spec runtime_failure(atom(), String.t(), term()) :: t()
  def runtime_failure(code, message, details \\ nil)
      when is_atom(code) and is_binary(message) do
    %__MODULE__{
      code: code,
      message: message,
      details: details,
      exit_code: 1,
      retryable?: retryable_code?(code)
    }
  end

  # ── Normalization ───────────────────────────────────────────────

  @doc """
  Converts a raw error reason into a normalized `%Error{}`.

  Accepts an existing `%Error{}`, an `{:error, reason}` tuple, or any
  raw term. When the input is already an `%Error{}`, provider and
  operation fields are back-filled if they were blank.

  ## Examples

      iex> normalize("cnb", :pr_view, :missing_cnb_token)
      %Error{provider: "cnb", operation: :pr_view, code: :missing_cnb_token, ...}

      iex> normalize("github", :api, {:error, %Error{code: :timeout}})
      %Error{provider: "github", operation: :api, code: :timeout, ...}
  """
  @spec normalize(map() | String.t() | nil, atom() | String.t(), term()) :: t()
  def normalize(provider_or_repo, operation, {:error, reason}) do
    normalize(provider_or_repo, operation, reason)
  end

  def normalize(provider_or_repo, operation, %__MODULE__{} = error) do
    provider = to_provider(provider_or_repo)

    %__MODULE__{
      error
      | provider: if(error.provider in [nil, "", "unknown"], do: provider, else: error.provider),
        operation: if(is_nil(error.operation), do: operation, else: error.operation)
    }
  end

  def normalize(provider_or_repo, operation, reason) do
    provider = to_provider(provider_or_repo)
    normalize(provider_or_repo, operation, normalized_reason(provider, reason))
  end

  @spec retryable?(t() | term()) :: boolean()
  def retryable?(%__MODULE__{retryable?: retryable?}), do: retryable? == true
  def retryable?(_reason), do: false

  # ── Helpers ──────────────────────────────────────────────────────

  @retryable_codes ~w(
    cnb_api_request
    cnb_api_status
    github_api_failed
    github_run_list_failed
    github_run_view_failed
  )a

  defp retryable_code?(code) when code in @retryable_codes, do: true
  defp retryable_code?(_code), do: false

  defp retryable_reason?({:cnb_api_request, _, _, _}), do: true
  defp retryable_reason?({:cnb_api_status, _, _, _, _}), do: true
  defp retryable_reason?(_reason), do: false

  defp normalized_reason("cnb", :missing_cnb_token),
    do: runtime_failure(:missing_cnb_token, "CNB provider requires CNB_TOKEN")

  defp normalized_reason("cnb", :missing_cnb_repository_slug),
    do: runtime_failure(:missing_cnb_repository_slug, "CNB provider requires a repository slug")

  defp normalized_reason(provider, {:unsupported_repo_provider_kind, kind}) do
    %__MODULE__{
      code: :unsupported_provider,
      message: "Repo provider kind #{inspect(kind)} is not supported.",
      details: %{kind: kind, source_reason: {:unsupported_repo_provider_kind, kind}},
      provider: kind || provider,
      exit_code: 64
    }
  end

  defp normalized_reason(provider, {:unsupported_repo_provider_option, kind, option}) do
    unsupported_option(kind || provider, option)
  end

  defp normalized_reason(_provider, reason) do
    %__MODULE__{
      code: error_code(reason),
      message: error_message(reason),
      details: %{source_reason: reason},
      exit_code: 1,
      retryable?: retryable_reason?(reason)
    }
  end

  defp error_code({tag, _}) when is_atom(tag), do: tag
  defp error_code({tag, _, _}) when is_atom(tag), do: tag
  defp error_code({tag, _, _, _}) when is_atom(tag), do: tag
  defp error_code({tag, _, _, _, _}) when is_atom(tag), do: tag
  defp error_code(reason) when is_atom(reason), do: reason
  defp error_code(_reason), do: :unknown

  defp error_message(reason) when is_atom(reason), do: "Repo provider operation failed: #{reason}"
  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: "Repo provider operation failed: #{inspect(reason)}"

  defp unsupported_option_message(kind, :required_pr_label) do
    "repo.provider.options.required_pr_label requires repo.provider.kind to be github; current provider: #{kind}"
  end

  defp unsupported_option_message(kind, option) do
    "Repo provider #{kind || "unknown"} does not support option #{option}"
  end

  defp to_provider(%{} = provider_or_repo) do
    case RepoConfig.kind(provider_or_repo) || Map.get(provider_or_repo, :kind) || Map.get(provider_or_repo, "kind") do
      kind when is_binary(kind) and kind != "" -> kind
      kind when is_atom(kind) -> Atom.to_string(kind)
      _other -> "unknown"
    end
  end

  defp to_provider(provider) when is_binary(provider) and provider != "", do: provider
  defp to_provider(provider) when is_atom(provider) and not is_nil(provider), do: Atom.to_string(provider)
  defp to_provider(_provider), do: "unknown"
end
