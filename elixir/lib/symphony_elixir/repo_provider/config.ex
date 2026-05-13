defmodule SymphonyElixir.RepoProvider.Config do
  @moduledoc """
  Typed configuration struct for the repo-provider subsystem.

  The public contract between the configuration layer and repo-provider
  adapters is intentionally small:

    * `path` - repo-core context: local target repository path for reads
    * `remote` - repo-core context: local target repository remote settings
    * `base_branch` - repo-core context: default base branch for proposals
    * `branch` - repo-core context: generated branch-name settings
    * `provider` - provider selection and provider-owned options
    * `runtime` - ephemeral runtime-only settings

  The repo-core context fields are pass-through inputs for provider adapters that
  need to consume local Git facts through `SymphonyElixir.Repo` or
  `SymphonyElixir.Repo.Context`. They are not provider-owned semantics:
  repo-provider code must not redefine branch, remote, status, fetch, commit, or
  push behavior.

  Adapters should prefer the accessors in this module instead of reaching
  into nested maps directly. The accessors normalize both atom and string
  keys so callers can transition incrementally from raw maps to `%Config{}`.
  """

  alias SymphonyElixir.Config, as: RuntimeSettings

  defstruct [:path, :base_branch, remote: %{}, branch: %{}, provider: %{}, runtime: %{}]

  @type t :: %__MODULE__{
          path: String.t() | nil,
          base_branch: String.t() | nil,
          remote: map(),
          branch: map(),
          provider: map(),
          runtime: map()
        }

  @spec current() :: {:ok, t()} | {:error, term()}
  def current do
    with {:ok, settings} <- RuntimeSettings.settings() do
      {:ok, new(settings.repo)}
    end
  end

  @spec current!() :: t()
  def current! do
    RuntimeSettings.settings!().repo
    |> new()
  end

  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = repo), do: repo

  def new(repo) when is_map(repo) do
    %__MODULE__{
      path: field(repo, :path),
      base_branch: field(repo, :base_branch),
      remote: repo |> field(:remote) |> normalize_remote(),
      branch: repo |> field(:branch) |> normalize_branch(),
      provider: repo |> field(:provider) |> normalize_provider(),
      runtime: repo |> field(:runtime) |> normalize_runtime()
    }
  end

  @spec path(t() | map()) :: String.t() | nil
  def path(repo), do: field(repo, :path)

  @spec base_branch(t() | map()) :: String.t() | nil
  def base_branch(repo), do: field(repo, :base_branch)

  @spec remote(t() | map()) :: map()
  def remote(repo), do: field(repo, :remote) |> map_value()

  @spec remote_name(t() | map()) :: String.t() | nil
  def remote_name(repo), do: remote_value(repo, "name")

  @spec remote_url(t() | map()) :: String.t() | nil
  def remote_url(repo), do: remote_value(repo, "url")

  @spec remote_value(t() | map(), String.t()) :: term()
  def remote_value(repo, key) when is_binary(key), do: remote(repo) |> nested_value(key)

  @spec branch(t() | map()) :: map()
  def branch(repo), do: field(repo, :branch) |> map_value()

  @spec branch_work_prefix(t() | map()) :: String.t() | nil
  def branch_work_prefix(repo), do: branch_value(repo, "work_prefix")

  @spec branch_value(t() | map(), String.t()) :: term()
  def branch_value(repo, key) when is_binary(key), do: branch(repo) |> nested_value(key)

  @spec provider(t() | map()) :: map()
  def provider(repo), do: field(repo, :provider) |> map_value()

  @spec runtime(t() | map()) :: map()
  def runtime(repo), do: field(repo, :runtime) |> map_value()

  @spec kind(t() | map()) :: String.t() | nil
  def kind(repo), do: provider_value(repo, "kind")

  @spec repository(t() | map()) :: String.t() | nil
  def repository(repo), do: provider_value(repo, "repository")

  @spec api_base_url(t() | map()) :: String.t() | nil
  def api_base_url(repo), do: provider_value(repo, "api_base_url")

  @spec web_base_url(t() | map()) :: String.t() | nil
  def web_base_url(repo), do: provider_value(repo, "web_base_url")

  @spec provider_value(t() | map(), String.t()) :: term()
  def provider_value(repo, key) when is_binary(key), do: normalized_provider(repo) |> nested_value(key)

  @spec options(t() | map()) :: map()
  def options(repo), do: provider_value(repo, "options") |> map_value()

  @spec option(t() | map(), String.t()) :: term()
  def option(repo, key) when is_binary(key), do: options(repo) |> nested_value(key)

  @spec required_pr_label(t() | map()) :: String.t() | nil
  def required_pr_label(repo), do: option(repo, "required_pr_label")

  @spec change_proposal_body_generator(t() | map()) :: term()
  def change_proposal_body_generator(repo), do: option(repo, "change_proposal_body_generator")

  @spec runtime_http_timeout_seconds(t() | map()) :: String.t() | nil
  def runtime_http_timeout_seconds(repo), do: runtime_value(repo, "http_timeout_seconds")

  @spec runtime_max_http_retries(t() | map()) :: String.t() | nil
  def runtime_max_http_retries(repo), do: runtime_value(repo, "max_http_retries")

  @spec runtime_retry_backoff_seconds(t() | map()) :: String.t() | nil
  def runtime_retry_backoff_seconds(repo), do: runtime_value(repo, "retry_backoff_seconds")

  @spec runtime_value(t() | map(), String.t()) :: term()
  def runtime_value(repo, key) when is_binary(key), do: runtime(repo) |> nested_value(key)

  @spec with_kind(t() | map(), String.t()) :: t()
  def with_kind(repo, kind) when is_binary(kind) do
    config = new(repo)
    %__MODULE__{config | provider: Map.put(config.provider, :kind, kind)}
  end

  defp field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp field(_map, _key), do: nil

  defp normalized_provider(repo) when is_map(repo), do: new(repo).provider
  defp normalized_provider(_repo), do: %{}

  defp map_value(value) when is_map(value), do: value
  defp map_value(_value), do: %{}

  defp nested_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp nested_value(_map, _key), do: nil

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp normalize_provider(value) when is_map(value) do
    normalized = normalize_map(value)
    options = normalized |> nested_value("options") |> normalize_options()

    normalized
    |> maybe_put(:kind, nested_value(normalized, "kind"))
    |> maybe_put(:repository, nested_value(normalized, "repository"))
    |> maybe_put(:api_base_url, nested_value(normalized, "api_base_url"))
    |> maybe_put(:web_base_url, nested_value(normalized, "web_base_url"))
    |> maybe_put(:options, options)
  end

  defp normalize_provider(_value), do: %{}

  defp normalize_remote(value) when is_map(value) do
    normalized = normalize_map(value)

    normalized
    |> maybe_put(:name, nested_value(normalized, "name"))
    |> maybe_put(:url, nested_value(normalized, "url"))
  end

  defp normalize_remote(_value), do: %{}

  defp normalize_branch(value) when is_map(value) do
    normalized = normalize_map(value)

    normalized
    |> maybe_put(:work_prefix, nested_value(normalized, "work_prefix"))
  end

  defp normalize_branch(_value), do: %{}

  defp normalize_runtime(value) when is_map(value) do
    normalized = normalize_map(value)

    normalized
    |> maybe_put(:http_timeout_seconds, nested_value(normalized, "http_timeout_seconds"))
    |> maybe_put(:max_http_retries, nested_value(normalized, "max_http_retries"))
    |> maybe_put(:retry_backoff_seconds, nested_value(normalized, "retry_backoff_seconds"))
  end

  defp normalize_runtime(_value), do: %{}

  defp normalize_options(value) when is_map(value) do
    normalized = normalize_map(value)

    normalized
    |> maybe_put(:required_pr_label, nested_value(normalized, "required_pr_label"))
    |> maybe_put(:change_proposal_body_generator, nested_value(normalized, "change_proposal_body_generator"))
  end

  defp normalize_options(_value), do: %{}

  defp normalize_map(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> normalize_map()
  end

  defp normalize_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      Map.put(acc, key, normalize_map(value))
    end)
  end

  defp normalize_map(list) when is_list(list), do: Enum.map(list, &normalize_map/1)
  defp normalize_map(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
