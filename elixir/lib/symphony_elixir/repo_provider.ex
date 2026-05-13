defmodule SymphonyElixir.RepoProvider do
  @moduledoc """
  Facade for the pluggable repo-provider subsystem.

  This module is the only public entry point that application code should
  use. Internally it:

    1. Reads the current `%Config{}` or normalizes an explicit config
    2. Resolves the adapter via `Registry`
    3. Checks the adapter's declared capabilities
    4. Delegates through a telemetry-instrumented dispatch layer

  Every provider operation has two forms:

    * implicit - reads config from application state
    * explicit - accepts a repo config as the first argument
  """

  alias SymphonyElixir.RepoProvider.{
    Adapter,
    Config,
    Error,
    Registry,
    RuntimeConfig,
    ToolExecutor
  }

  @type repo_config :: Config.t()
  @type result(t) :: {:ok, t} | {:error, Error.t() | term()}
  @type capability :: Adapter.capability()

  @spec supported_kinds() :: [String.t()]
  def supported_kinds, do: Registry.supported_kinds()

  @spec default_kind() :: String.t()
  def default_kind, do: "github"

  @spec adapter() :: module()
  def adapter, do: current!() |> elem(0)

  @spec adapter(repo_config() | map()) :: module()
  def adapter(repo) when is_map(repo), do: Registry.fetch!(current_kind(repo))

  @spec adapter_for(term()) :: module() | nil
  def adapter_for(kind) when is_binary(kind), do: Registry.fetch(kind)
  def adapter_for(_kind), do: nil

  @spec defaults(term()) :: map()
  def defaults(kind) do
    case adapter_for(kind) do
      nil -> %{}
      module -> module.defaults()
    end
  end

  @spec capabilities() :: [capability()]
  def capabilities do
    case current() do
      {:ok, {module, _repo}} -> adapter_capabilities(module)
      {:error, _reason} -> []
    end
  end

  @spec capabilities(repo_config() | map()) :: [capability()]
  def capabilities(repo) when is_map(repo) do
    case current(repo) do
      {:ok, {module, _config}} -> adapter_capabilities(module)
      {:error, _reason} -> []
    end
  end

  def capabilities(_repo), do: []

  @spec supports?(capability()) :: boolean()
  def supports?(capability) when is_atom(capability), do: capability in capabilities()

  @spec supports?(repo_config() | map(), capability()) :: boolean()
  def supports?(repo, capability) when is_map(repo) and is_atom(capability) do
    capability in capabilities(repo)
  end

  def supports?(_repo, _capability), do: false

  @spec current_kind() :: String.t()
  def current_kind do
    case Config.current!() |> Config.kind() do
      kind when is_binary(kind) and kind != "" -> kind
      _other -> default_kind()
    end
  end

  @spec current_kind(repo_config() | map()) :: String.t()
  def current_kind(repo) when is_map(repo) do
    case repo |> Config.new() |> Config.kind() do
      kind when is_binary(kind) and kind != "" -> kind
      _other -> default_kind()
    end
  end

  def current_kind(_repo), do: default_kind()

  @spec validate_config(repo_config() | map()) :: :ok | {:error, term()}
  def validate_config(repo) when is_map(repo) do
    config = Config.new(repo)
    kind = current_kind(config)

    case adapter_for(kind) do
      nil ->
        {:error, Error.normalize(kind, :validate_config, {:unsupported_repo_provider_kind, kind})}

      module ->
        case dispatch(module, :validate_config, [config]) do
          :ok -> :ok
          {:error, reason} -> {:error, Error.normalize(config, :validate_config, reason)}
        end
    end
  end

  def validate_config(_repo),
    do: {:error, Error.normalize(nil, :validate_config, {:unsupported_repo_provider_kind, nil})}

  @spec runtime_env() :: [{String.t(), String.t()}]
  def runtime_env do
    runtime_env(Config.current!())
  end

  @spec runtime_env(repo_config() | map()) :: [{String.t(), String.t()}]
  def runtime_env(repo) when is_map(repo), do: RuntimeConfig.to_env(Config.new(repo))
  def runtime_env(_repo), do: RuntimeConfig.to_env(%{})

  # ── Dynamic tools ───────────────────────────────────────────────

  @spec dynamic_tools() :: [map()]
  def dynamic_tools, do: dynamic_tools(Config.current!())

  @spec dynamic_tools(repo_config() | map()) :: [map()]
  def dynamic_tools(repo) when is_map(repo), do: ToolExecutor.tool_specs(Config.new(repo))
  def dynamic_tools(_repo), do: []

  @spec execute_dynamic_tool(String.t() | nil, term(), keyword()) ::
          SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def execute_dynamic_tool(tool, arguments, opts \\ []) do
    execute_dynamic_tool(Config.current!(), tool, arguments, opts)
  end

  @spec execute_dynamic_tool(repo_config() | map(), String.t() | nil, term(), keyword()) ::
          SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def execute_dynamic_tool(repo, tool, arguments, opts) when is_map(repo) and is_list(opts) do
    ToolExecutor.execute(Config.new(repo), tool, arguments, opts)
  end

  @spec auth_status(keyword()) :: result(String.t())
  def auth_status(opts \\ [])
  def auth_status(opts) when is_list(opts), do: call_optional(:auth_status, [opts], :unsupported)

  @spec auth_status(repo_config() | map()) :: result(String.t())
  def auth_status(repo) when is_map(repo), do: auth_status(repo, [])

  @spec auth_status(repo_config() | map(), keyword()) :: result(String.t())
  def auth_status(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :auth_status, [opts], :unsupported)

  @spec pr_view(keyword()) :: result(map())
  def pr_view(opts \\ [])
  def pr_view(opts) when is_list(opts), do: call_optional(:pr_view, [opts], :unsupported)

  @spec pr_view(repo_config() | map()) :: result(map())
  def pr_view(repo) when is_map(repo), do: pr_view(repo, [])

  @spec pr_view(repo_config() | map(), keyword()) :: result(map())
  def pr_view(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :pr_view, [opts], :unsupported)

  @spec pr_create(keyword()) :: result(String.t())
  def pr_create(opts \\ [])
  def pr_create(opts) when is_list(opts), do: call_optional(:pr_create, [opts], :unsupported)

  @spec pr_create(repo_config() | map()) :: result(String.t())
  def pr_create(repo) when is_map(repo), do: pr_create(repo, [])

  @spec pr_create(repo_config() | map(), keyword()) :: result(String.t())
  def pr_create(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :pr_create, [opts], :unsupported)

  @spec pr_edit(keyword()) :: result(String.t())
  def pr_edit(opts \\ [])
  def pr_edit(opts) when is_list(opts), do: call_optional(:pr_edit, [opts], :unsupported)

  @spec pr_edit(repo_config() | map()) :: result(String.t())
  def pr_edit(repo) when is_map(repo), do: pr_edit(repo, [])

  @spec pr_edit(repo_config() | map(), keyword()) :: result(String.t())
  def pr_edit(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :pr_edit, [opts], :unsupported)

  @spec pr_add_label(keyword()) :: result(String.t())
  def pr_add_label(opts \\ [])

  def pr_add_label(opts) when is_list(opts),
    do: call_optional(:pr_add_label, [opts], :unsupported)

  @spec pr_add_label(repo_config() | map()) :: result(String.t())
  def pr_add_label(repo) when is_map(repo), do: pr_add_label(repo, [])

  @spec pr_add_label(repo_config() | map(), keyword()) :: result(String.t())
  def pr_add_label(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :pr_add_label, [opts], :unsupported)

  @spec pr_issue_comments(keyword()) :: result([map()])
  def pr_issue_comments(opts \\ [])

  def pr_issue_comments(opts) when is_list(opts),
    do: call_optional(:pr_issue_comments, [opts], :unsupported)

  @spec pr_issue_comments(repo_config() | map()) :: result([map()])
  def pr_issue_comments(repo) when is_map(repo), do: pr_issue_comments(repo, [])

  @spec pr_issue_comments(repo_config() | map(), keyword()) :: result([map()])
  def pr_issue_comments(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :pr_issue_comments, [opts], :unsupported)

  @spec pr_add_issue_comment(keyword()) :: result(map())
  def pr_add_issue_comment(opts \\ [])

  def pr_add_issue_comment(opts) when is_list(opts),
    do: call_optional(:pr_add_issue_comment, [opts], :unsupported)

  @spec pr_add_issue_comment(repo_config() | map()) :: result(map())
  def pr_add_issue_comment(repo) when is_map(repo), do: pr_add_issue_comment(repo, [])

  @spec pr_add_issue_comment(repo_config() | map(), keyword()) :: result(map())
  def pr_add_issue_comment(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :pr_add_issue_comment, [opts], :unsupported)

  @spec pr_reviews(keyword()) :: result([map()])
  def pr_reviews(opts \\ [])

  def pr_reviews(opts) when is_list(opts),
    do: call_optional(:pr_reviews, [opts], :unsupported)

  @spec pr_reviews(repo_config() | map()) :: result([map()])
  def pr_reviews(repo) when is_map(repo), do: pr_reviews(repo, [])

  @spec pr_reviews(repo_config() | map(), keyword()) :: result([map()])
  def pr_reviews(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :pr_reviews, [opts], :unsupported)

  @spec pr_submit_review(keyword()) :: result(map())
  def pr_submit_review(opts \\ [])

  def pr_submit_review(opts) when is_list(opts),
    do: call_optional(:pr_submit_review, [opts], :unsupported)

  @spec pr_submit_review(repo_config() | map()) :: result(map())
  def pr_submit_review(repo) when is_map(repo), do: pr_submit_review(repo, [])

  @spec pr_submit_review(repo_config() | map(), keyword()) :: result(map())
  def pr_submit_review(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :pr_submit_review, [opts], :unsupported)

  @spec pr_review_comments(keyword()) :: result([map()])
  def pr_review_comments(opts \\ [])

  def pr_review_comments(opts) when is_list(opts),
    do: call_optional(:pr_review_comments, [opts], :unsupported)

  @spec pr_review_comments(repo_config() | map()) :: result([map()])
  def pr_review_comments(repo) when is_map(repo), do: pr_review_comments(repo, [])

  @spec pr_review_comments(repo_config() | map(), keyword()) :: result([map()])
  def pr_review_comments(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :pr_review_comments, [opts], :unsupported)

  @spec pr_reply_review_comment(keyword()) :: result(map())
  def pr_reply_review_comment(opts \\ [])

  def pr_reply_review_comment(opts) when is_list(opts),
    do: call_optional(:pr_reply_review_comment, [opts], :unsupported)

  @spec pr_reply_review_comment(repo_config() | map()) :: result(map())
  def pr_reply_review_comment(repo) when is_map(repo), do: pr_reply_review_comment(repo, [])

  @spec pr_reply_review_comment(repo_config() | map(), keyword()) :: result(map())
  def pr_reply_review_comment(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :pr_reply_review_comment, [opts], :unsupported)

  @spec pr_close(keyword()) :: result(String.t())
  def pr_close(opts \\ [])
  def pr_close(opts) when is_list(opts), do: call_optional(:pr_close, [opts], :unsupported)

  @spec pr_close(repo_config() | map()) :: result(String.t())
  def pr_close(repo) when is_map(repo), do: pr_close(repo, [])

  @spec pr_close(repo_config() | map(), keyword()) :: result(String.t())
  def pr_close(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :pr_close, [opts], :unsupported)

  @spec pr_merge(keyword()) :: result(String.t())
  def pr_merge(opts \\ [])
  def pr_merge(opts) when is_list(opts), do: call_optional(:pr_merge, [opts], :unsupported)

  @spec pr_merge(repo_config() | map()) :: result(String.t())
  def pr_merge(repo) when is_map(repo), do: pr_merge(repo, [])

  @spec pr_merge(repo_config() | map(), keyword()) :: result(String.t())
  def pr_merge(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :pr_merge, [opts], :unsupported)

  @spec pr_checks(keyword()) :: result([map()])
  def pr_checks(opts \\ [])
  def pr_checks(opts) when is_list(opts), do: call_optional(:pr_checks, [opts], :unsupported)

  @spec pr_checks(repo_config() | map()) :: result([map()])
  def pr_checks(repo) when is_map(repo), do: pr_checks(repo, [])

  @spec pr_checks(repo_config() | map(), keyword()) :: result([map()])
  def pr_checks(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :pr_checks, [opts], :unsupported)

  @spec api(keyword()) :: result(term())
  def api(opts \\ [])
  def api(opts) when is_list(opts), do: call_optional(:api, [opts], :unsupported)

  @spec api(repo_config() | map()) :: result(term())
  def api(repo) when is_map(repo), do: api(repo, [])

  @spec api(repo_config() | map(), keyword()) :: result(term())
  def api(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :api, [opts], :unsupported)

  @spec run_list(keyword()) :: result([map()])
  def run_list(opts \\ [])
  def run_list(opts) when is_list(opts), do: call_optional(:run_list, [opts], :unsupported)

  @spec run_list(repo_config() | map()) :: result([map()])
  def run_list(repo) when is_map(repo), do: run_list(repo, [])

  @spec run_list(repo_config() | map(), keyword()) :: result([map()])
  def run_list(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :run_list, [opts], :unsupported)

  @spec run_view(keyword()) :: result(map() | String.t())
  def run_view(opts \\ [])
  def run_view(opts) when is_list(opts), do: call_optional(:run_view, [opts], :unsupported)

  @spec run_view(repo_config() | map()) :: result(map() | String.t())
  def run_view(repo) when is_map(repo), do: run_view(repo, [])

  @spec run_view(repo_config() | map(), keyword()) :: result(map() | String.t())
  def run_view(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :run_view, [opts], :unsupported)

  @spec close_open_pull_requests_for_branch(repo_config() | map(), String.t() | nil, keyword()) ::
          :ok | {:error, term()}
  def close_open_pull_requests_for_branch(repo, branch, opts \\ [])

  def close_open_pull_requests_for_branch(_repo, nil, _opts), do: :ok

  def close_open_pull_requests_for_branch(repo, branch, opts)
      when is_map(repo) and is_binary(branch) and is_list(opts) do
    config = Config.new(repo)
    kind = current_kind(config)

    case adapter_for(kind) do
      nil ->
        {:error, Error.unsupported_provider(kind)}

      module ->
        optional(
          module,
          :close_open_pull_requests_for_branch,
          [config, branch, opts],
          :ok,
          config
        )
    end
  end

  # ── Healthcheck ──────────────────────────────────────────────────

  @spec healthcheck(keyword()) :: :ok | {:error, Error.t() | term()}
  def healthcheck(opts \\ [])
  def healthcheck(opts) when is_list(opts), do: call_optional(:healthcheck, [opts], :ok)

  @spec healthcheck(repo_config() | map()) :: :ok | {:error, Error.t() | term()}
  def healthcheck(repo) when is_map(repo), do: healthcheck(repo, [])

  @spec healthcheck(repo_config() | map(), keyword()) :: :ok | {:error, Error.t() | term()}
  def healthcheck(repo, opts) when is_map(repo) and is_list(opts),
    do: call_optional(repo, :healthcheck, [opts], :ok)

  @spec dispatch(module(), atom(), list()) :: term()
  defp dispatch(module, callback, args) when is_atom(module) do
    metadata = %{adapter: module, callback: callback}

    :telemetry.span(
      [:symphony, :repo_provider, :dispatch],
      metadata,
      fn ->
        result = apply(module, callback, args)
        {result, Map.put(metadata, :result, result_tag(result))}
      end
    )
  end

  defp call_optional(callback, extra_args, default)
       when is_atom(callback) and is_list(extra_args) do
    case current() do
      {:ok, {module, repo}} ->
        optional(module, callback, [repo | extra_args], default, repo)

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp call_optional(repo, callback, extra_args, default)
       when is_map(repo) and is_atom(callback) and is_list(extra_args) do
    case current(repo) do
      {:ok, {module, config}} ->
        optional(module, callback, [config | extra_args], default, config)

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp optional(module, callback, args, default, repo) when is_atom(module) do
    if supports_capability?(module, callback) do
      if function_exported?(module, callback, length(args)) do
        dispatch(module, callback, args)
        |> normalize_dispatch_result(repo, callback)
      else
        invalid_capability_error(repo, module, callback)
      end
    else
      default_for(default, repo, callback)
    end
  end

  defp default_for(:unsupported, repo, callback),
    do: {:error, Error.unsupported_capability(current_kind(repo), callback)}

  defp default_for(default, _repo, _callback), do: default

  defp normalize_dispatch_result(:ok, _repo, _callback), do: :ok
  defp normalize_dispatch_result({:ok, _value} = ok, _repo, _callback), do: ok

  defp normalize_dispatch_result({:error, reason}, repo, callback) do
    {:error, Error.normalize(repo, callback, reason)}
  end

  defp normalize_dispatch_result(other, _repo, _callback), do: other

  defp result_tag(:ok), do: :ok
  defp result_tag({:ok, _}), do: :ok
  defp result_tag({:error, _}), do: :error
  defp result_tag(_), do: :ok

  defp current do
    repo = Config.current!()
    current(repo)
  end

  defp current(repo) when is_map(repo) do
    config = Config.new(repo)
    kind = current_kind(config)

    case adapter_for(kind) do
      nil -> {:error, Error.unsupported_provider(kind)}
      module -> {:ok, {module, config}}
    end
  end

  defp current! do
    repo = Config.current!()
    {adapter(repo), repo}
  end

  defp supports_capability?(module, capability) when is_atom(module) and is_atom(capability) do
    capability in adapter_capabilities(module)
  end

  defp adapter_capabilities(module) when is_atom(module) do
    Code.ensure_loaded(module)

    declared_capabilities =
      if function_exported?(module, :capabilities, 0) do
        module.capabilities()
      else
        []
      end

    Adapter.all_capabilities()
    |> Enum.filter(&(&1 in List.wrap(declared_capabilities)))
  end

  defp invalid_capability_error(repo, module, capability) do
    kind = current_kind(repo)

    {:error,
     Error.normalize(
       repo,
       capability,
       Error.runtime_failure(
         :invalid_adapter_capability,
         "Repo provider #{kind} declares capability #{capability} but #{inspect(module)} does not implement #{capability}/#{callback_arity(capability)}",
         %{adapter: module, capability: capability}
       )
     )}
  end

  defp callback_arity(capability) when is_atom(capability) do
    Adapter.capability_callbacks()
    |> Map.get(capability)
  end
end
