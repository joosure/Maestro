defmodule SymphonyElixir.MixProject do
  use Mix.Project

  @default_coverage_threshold 70

  def project do
    [
      app: :symphony_elixir,
      version: "0.1.0",
      elixir: "~> 1.19",
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      test_coverage: [
        summary: [
          threshold: coverage_threshold()
        ],
        ignore_modules: [
          SymphonyElixir.Application,
          SymphonyElixir.CLI,
          SymphonyElixir.Config,
          SymphonyElixir.Config.InputNormalizer,
          SymphonyElixir.Config.SandboxPolicy,
          SymphonyElixir.Config.Schema,
          SymphonyElixir.Config.Schema.Worker,
          SymphonyElixir.Config.TrackerSettingsFinalizer,
          SymphonyElixir.HttpServer,
          SymphonyElixir.Issue,
          SymphonyElixir.Issue.Lifecycle,
          SymphonyElixir.Observability.Event,
          SymphonyElixir.Observability.EventStore,
          SymphonyElixir.Observability.Fields,
          SymphonyElixir.Observability.Formatter,
          SymphonyElixir.Observability.LogFile,
          SymphonyElixir.Observability.Logger,
          SymphonyElixir.Observability.Redaction,
          SymphonyElixir.Observability.StatusDashboard,
          SymphonyElixir.Observability.StatusDashboard.Drilldown,
          SymphonyElixir.Observability.StatusDashboard.Presenter,
          SymphonyElixir.Observability.StatusDashboard.RateLimits,
          SymphonyElixir.Observability.StatusDashboard.Throughput,
          SymphonyElixir.Orchestrator,
          SymphonyElixir.Orchestrator.Dispatch,
          SymphonyElixir.Orchestrator.Events,
          SymphonyElixir.Orchestrator.Launch,
          SymphonyElixir.Orchestrator.Polling,
          SymphonyElixir.Orchestrator.Retry,
          SymphonyElixir.Orchestrator.Running,
          SymphonyElixir.Orchestrator.RuntimeState,
          SymphonyElixir.Orchestrator.Snapshot,
          SymphonyElixir.Orchestrator.State,
          SymphonyElixir.Orchestrator.TerminalCleanup,
          SymphonyElixir.Orchestrator.WorkerHosts,
          SymphonyElixir.SSH,
          SymphonyElixir.SpecsCheck,
          SymphonyElixir.Tracker,
          SymphonyElixir.Tracker.Linear.Adapter,
          SymphonyElixir.Tracker.Linear.Client,
          SymphonyElixir.Tracker.Linear.Normalizer,
          SymphonyElixir.Tracker.Memory,
          SymphonyElixir.Tracker.Tapd.Adapter,
          SymphonyElixir.Tracker.Tapd.Client,
          SymphonyElixir.Tracker.Tapd.CommentCodec,
          SymphonyElixir.Tracker.Tapd.Normalizer,
          SymphonyElixir.Tracker.Tapd.WorkflowConfig,
          SymphonyElixir.Workflow,
          SymphonyElixir.Workflow.RoutePolicy,
          SymphonyElixir.Workflow.Store,
          SymphonyElixir.Workspace,
          SymphonyElixir.Workspace.Bootstrap,
          SymphonyElixir.Workspace.Cleanup,
          SymphonyElixir.Workspace.Context,
          SymphonyElixir.Workspace.Hooks,
          SymphonyElixir.Workspace.Paths,
          SymphonyElixir.Workspace.Remote,
          SymphonyElixirWeb.DashboardLive,
          SymphonyElixirWeb.Endpoint,
          SymphonyElixirWeb.ErrorHTML,
          SymphonyElixirWeb.ErrorJSON,
          SymphonyElixirWeb.Layouts,
          SymphonyElixirWeb.ObservabilityApiController,
          SymphonyElixirWeb.ObservabilityPubSub,
          SymphonyElixirWeb.Presenter,
          SymphonyElixirWeb.Router,
          SymphonyElixirWeb.Router.Helpers,
          SymphonyElixirWeb.StaticAssetController,
          SymphonyElixirWeb.StaticAssets
        ]
      ],
      test_ignore_filters: [
        "test/support/snapshot_support.exs",
        "test/support/test_support.exs",
        "test/support/repo_provider_adapter_contract.ex",
        "test/support/tracker_adapter_contract.ex",
        "test/support/workflow_profile_contract.ex"
      ],
      dialyzer: [
        plt_add_apps: [:mix]
      ],
      escript: escript(),
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {SymphonyElixir.Application, []},
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "worker_daemon.check": :test
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 1.8"},
      {:floki, ">= 0.30.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix, "~> 1.8.0"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_view, "~> 1.1.0"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.12"},
      {:solid, "~> 1.2"},
      {:ecto, "~> 3.13"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      build: ["escript.build"],
      lint: ["specs.check", "credo --strict"],
      "worker_daemon.check": [
        "specs.check",
        "test test/symphony_worker_daemon/config_test.exs test/symphony_worker_daemon/cli_test.exs test/symphony_worker_daemon/server_test.exs test/symphony_worker_daemon/bridge_proxy_test.exs test/symphony_worker_daemon/provider_app_server_test.exs test/symphony_elixir/agent/runtime/worker_daemon_test.exs test/symphony_elixir/agent/runtime/dynamic_tool_bridge_test.exs"
      ]
    ]
  end

  defp escript do
    [
      app: nil,
      include_priv_for: [:symphony_elixir],
      main_module: SymphonyElixir.CLI,
      name: "symphony",
      path: "bin/symphony"
    ]
  end

  defp coverage_threshold do
    case System.get_env("SYMPHONY_TEST_COVERAGE_THRESHOLD") do
      nil ->
        @default_coverage_threshold

      value ->
        parse_coverage_threshold(value)
    end
  end

  defp parse_coverage_threshold(value) when is_binary(value) do
    case Integer.parse(value) do
      {threshold, ""} when threshold >= 0 and threshold <= 100 ->
        threshold

      _other ->
        raise """
        Invalid SYMPHONY_TEST_COVERAGE_THRESHOLD=#{inspect(value)}.
        Expected an integer between 0 and 100.
        """
    end
  end
end
