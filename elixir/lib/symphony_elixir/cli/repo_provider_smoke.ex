defmodule SymphonyElixir.CLI.RepoProviderSmoke do
  @moduledoc false

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.RepoProvider.CLI.Evaluator
  alias SymphonyElixir.RepoProvider.Kinds
  alias SymphonyElixir.RepoProvider.RuntimeConfig
  alias SymphonyElixir.RepoProvider.Smoke

  @switches [
    provider: :string,
    repo: :string,
    pr: :string,
    api_endpoint: :string,
    api_jq: :string,
    destructive: :boolean,
    auto_provision_cnb_pipeline: :boolean,
    head: :string,
    base: :string,
    title: :string,
    body: :string,
    json: :boolean,
    help: :boolean
  ]

  @type deps :: %{
          env: (-> %{optional(String.t()) => String.t()} | [{String.t(), String.t()}]),
          command_opts: (-> keyword()),
          cli_evaluate: ([String.t()], map() -> {String.t(), String.t(), non_neg_integer()}),
          monotonic_time_ms: (-> integer()),
          emit_event: (atom(), atom(), map() -> map())
        }

  @spec evaluate([String.t()], deps()) :: {String.t(), String.t(), non_neg_integer()}
  def evaluate(argv, deps \\ runtime_deps()) when is_list(argv) and is_map(deps) do
    case OptionParser.parse(argv, strict: @switches, aliases: [h: :help]) do
      {opts, [], []} ->
        env_map = normalize_env(deps.env.())

        if opts[:help] do
          {usage(), "", 0}
        else
          case validate_opts(opts, env_map) do
            :ok -> render_smoke(opts, deps, env_map)
            {:error, message} -> {"", message <> "\n" <> usage(), 64}
          end
        end

      {_opts, unexpected, []} ->
        {"", "Unexpected argument(s): #{inspect(unexpected)}\n" <> usage(), 64}

      {_opts, _argv, invalid} ->
        {"", "Invalid option(s): #{inspect(invalid)}\n" <> usage(), 64}
    end
  end

  defp render_smoke(opts, deps, env_map) do
    command_opts = command_opts(deps)

    report =
      [
        provider: Keyword.get(opts, :provider),
        repo: Keyword.get(opts, :repo),
        pr: Keyword.get(opts, :pr),
        api_endpoint: Keyword.get(opts, :api_endpoint),
        api_jq: Keyword.get(opts, :api_jq),
        destructive: Keyword.get(opts, :destructive, false),
        auto_provision_cnb_pipeline: Keyword.get(opts, :auto_provision_cnb_pipeline, false),
        head: Keyword.get(opts, :head),
        base: Keyword.get(opts, :base),
        title: Keyword.get(opts, :title),
        body: Keyword.get(opts, :body)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Smoke.run(%{
        env: fn -> env_map end,
        command_opts: fn -> command_opts end,
        cli_evaluate: deps.cli_evaluate,
        monotonic_time_ms: deps.monotonic_time_ms,
        emit_event: deps.emit_event
      })

    output =
      if opts[:json] do
        Jason.encode!(Smoke.to_map(report)) <> "\n"
      else
        Smoke.format_text(report)
      end

    {output, "", if(report.ok, do: 0, else: 1)}
  end

  defp runtime_deps do
    %{
      env: &System.get_env/0,
      command_opts: fn -> [] end,
      cli_evaluate: &Evaluator.evaluate/2,
      monotonic_time_ms: fn -> System.monotonic_time(:millisecond) end,
      emit_event: &ObservabilityLogger.emit/3
    }
  end

  defp normalize_env(env) when is_map(env), do: env
  defp normalize_env(env) when is_list(env), do: Map.new(env)

  defp validate_opts(opts, env_map) do
    validation = smoke_validation_context(opts, env_map)

    cond do
      missing_api_endpoint_for_query?(validation) ->
        {:error, "--api-jq requires --api-endpoint"}

      auto_provision_requires_destructive?(validation) ->
        {:error, "--auto-provision-cnb-pipeline requires --destructive"}

      unsupported_auto_provision_provider?(validation) ->
        {:error, "--auto-provision-cnb-pipeline is only supported for --provider cnb"}

      auto_provision_with_head?(validation) ->
        {:error, "--auto-provision-cnb-pipeline does not accept --head"}

      destructive_with_pr?(validation) ->
        {:error, "Destructive smoke does not accept --pr"}

      destructive_with_api_probe?(validation) ->
        {:error, "Destructive smoke does not accept --api-endpoint or --api-jq"}

      destructive_without_required_head?(validation) ->
        {:error, "Destructive smoke requires --head unless --auto-provision-cnb-pipeline is enabled"}

      destructive_only_options_without_flag?(validation) ->
        {:error, "--head, --base, --title, --body, and --auto-provision-cnb-pipeline require --destructive"}

      true ->
        :ok
    end
  end

  defp smoke_validation_context(opts, env_map) do
    %{
      destructive?: Keyword.get(opts, :destructive, false),
      auto_provision_cnb_pipeline?: Keyword.get(opts, :auto_provision_cnb_pipeline, false),
      pr: Keyword.get(opts, :pr),
      api_endpoint: Keyword.get(opts, :api_endpoint),
      api_jq: Keyword.get(opts, :api_jq),
      head: blank_to_nil(Keyword.get(opts, :head)),
      base: blank_to_nil(Keyword.get(opts, :base)),
      title: blank_to_nil(Keyword.get(opts, :title)),
      body: blank_to_nil(Keyword.get(opts, :body)),
      provider_kind: blank_to_nil(Keyword.get(opts, :provider)) || env_map |> RuntimeConfig.from_env() |> RuntimeConfig.current_kind()
    }
  end

  defp missing_api_endpoint_for_query?(%{api_jq: api_jq, api_endpoint: api_endpoint}),
    do: api_jq && !api_endpoint

  defp auto_provision_requires_destructive?(%{auto_provision_cnb_pipeline?: true, destructive?: false}), do: true
  defp auto_provision_requires_destructive?(_validation), do: false

  defp unsupported_auto_provision_provider?(%{auto_provision_cnb_pipeline?: true, provider_kind: provider_kind}),
    do: provider_kind != Kinds.cnb()

  defp unsupported_auto_provision_provider?(_validation), do: false

  defp auto_provision_with_head?(%{auto_provision_cnb_pipeline?: true, head: head}), do: is_binary(head)
  defp auto_provision_with_head?(_validation), do: false

  defp destructive_with_pr?(%{destructive?: true, pr: pr}), do: is_binary(pr)
  defp destructive_with_pr?(_validation), do: false

  defp destructive_with_api_probe?(%{destructive?: true, api_endpoint: api_endpoint}), do: is_binary(api_endpoint)
  defp destructive_with_api_probe?(_validation), do: false

  defp destructive_without_required_head?(%{
         destructive?: true,
         auto_provision_cnb_pipeline?: false,
         head: nil
       }),
       do: true

  defp destructive_without_required_head?(_validation), do: false

  defp destructive_only_options_without_flag?(%{
         destructive?: false,
         auto_provision_cnb_pipeline?: auto_provision_cnb_pipeline?,
         head: head,
         base: base,
         title: title,
         body: body
       }) do
    auto_provision_cnb_pipeline? || Enum.any?([head, base, title, body], &is_binary/1)
  end

  defp destructive_only_options_without_flag?(_validation), do: false

  defp command_opts(deps) do
    case Map.get(deps, :command_opts) do
      nil -> []
      fun when is_function(fun, 0) -> fun.()
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp usage do
    """
    Usage:
      symphony repo-provider smoke [--provider <kind>] [--repo <slug>] [--pr <number>] [--api-endpoint <path>] [--api-jq <expr>] [--json]
      symphony repo-provider smoke [--provider <kind>] [--repo <slug>] --destructive --head <branch> [--base <branch>] [--title <text>] [--body <text>] [--json]
      symphony repo-provider smoke [--provider cnb] [--repo <slug>] --destructive --auto-provision-cnb-pipeline [--base <branch>] [--title <text>] [--body <text>] [--json]

    By default this read-only smoke probes:
      - current-kind
      - auth-status

    Optional probes:
      --pr <number>          Add pr-view, pr-reviews, and pr-checks for the given PR.
      --api-endpoint <path>  Add a read-only api GET probe.
      --api-jq <expr>        Optional query applied to the api probe payload.
      --destructive          Opt into write-path smoke that creates, edits, verifies, and closes a PR.
      --head <branch>        Required for destructive smoke. The source branch must already exist remotely.
      --auto-provision-cnb-pipeline
                             CNB-only destructive mode. Creates a temporary branch, writes a minimal .cnb.yml,
                             validates run-list/run-view --log, then closes the PR and deletes the branch.
      --base <branch>        Optional target branch override for destructive smoke.
      --title <text>         Optional destructive smoke PR title override.
      --body <text>          Optional destructive smoke PR body override.
      --json                 Emit machine-readable JSON instead of text.
    """
  end
end
