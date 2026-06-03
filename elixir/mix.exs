defmodule SymphonyElixir.MixProject do
  use Mix.Project

  @default_coverage_threshold 70

  def project do
    ensure_pinned_toolchain!()

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
      releases: releases(),
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
      emu_args: "+B i",
      name: "symphony",
      # Keep bin/symphony as the stable launcher that owns signal handling.
      path: "bin/symphony.escript"
    ]
  end

  defp releases do
    [
      symphony: [
        applications: [symphony_elixir: :none],
        include_executables_for: [:unix],
        include_erts: true
      ]
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

  defp ensure_pinned_toolchain! do
    pinned = pinned_toolchain!()
    actual_elixir = System.version()
    actual_otp = System.otp_release()

    unless actual_elixir == pinned.elixir and actual_otp == pinned.otp do
      raise """
      Elixir/OTP toolchain mismatch.

      Expected: Elixir #{pinned.elixir} / OTP #{pinned.otp}
      Actual:   Elixir #{actual_elixir} / OTP #{actual_otp}

      This project is pinned by elixir/mise.toml. Use the pinned toolchain:

          cd elixir
          mise trust
          mise install
          mise exec -- mix <task>
      """
    end
  end

  defp pinned_toolchain! do
    mise_path = Path.join(__DIR__, "mise.toml")
    contents = File.read!(mise_path)

    erlang_version = parse_mise_tool!(contents, "erlang")
    elixir_version = parse_mise_tool!(contents, "elixir")

    case Regex.run(~r/^(.+)-otp-(\d+)$/, elixir_version) do
      [_, pinned_elixir, elixir_otp] ->
        erlang_otp = erlang_version |> String.split(".", parts: 2) |> hd()

        unless erlang_otp == elixir_otp do
          raise """
          Invalid elixir/mise.toml toolchain pin.

          Erlang OTP #{erlang_otp} does not match Elixir build suffix OTP #{elixir_otp}.
          """
        end

        %{elixir: pinned_elixir, otp: erlang_otp}

      _other ->
        raise """
        Invalid elixir/mise.toml Elixir pin: #{inspect(elixir_version)}.

        Expected a value like "1.19.5-otp-28".
        """
    end
  end

  defp parse_mise_tool!(contents, tool) do
    pattern = ~r/^\s*#{Regex.escape(tool)}\s*=\s*"([^"]+)"\s*$/m

    case Regex.run(pattern, contents) do
      [_, version] ->
        version

      _other ->
        raise """
        Missing #{tool} tool pin in elixir/mise.toml.
        """
    end
  end
end
