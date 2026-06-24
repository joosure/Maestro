import Config

config :symphony_elixir, env: config_env()

config :symphony_elixir, :storage, backend: :sqlite

config :symphony_elixir, :storage_table_catalog,
  sources: [
    SymphonyElixir.AssemblyCatalog.StorageContracts
  ]

config :symphony_elixir, :workflow_runtime_extensions,
  sources: [
    SymphonyElixir.AssemblyCatalog.WorkflowExtensions
  ]

config :symphony_elixir, :capability_sources,
  catalogs: [
    SymphonyElixir.AssemblyCatalog.CapabilitySources
  ]

config :symphony_elixir, :agent_execution_plan, storage: :durable

config :symphony_elixir, :workflow_execution_plan_adoption, storage: :durable

config :symphony_elixir,
       :dynamic_tool_sources,
       catalogs: [
         SymphonyElixir.AssemblyCatalog.DynamicToolSources
       ]

config :symphony_elixir,
       :dynamic_tool_result_recorders,
       [
         SymphonyElixir.Workflow.DynamicToolResultRecorder
       ]

config :symphony_elixir,
       :dynamic_tool_failure_diagnostics,
       {SymphonyElixir.Workflow.StateTransitionReadiness.DynamicToolFailureDiagnostics, :fields, []}

config :symphony_elixir,
  ecto_repos: [SymphonyElixir.Storage.Repo]

storage_sqlite_path = Path.expand("../.symphony/storage/symphony.sqlite3", __DIR__)
storage_repo_priv = "priv/storage_repo"

config :symphony_elixir, SymphonyElixir.Storage.Repo,
  database: storage_sqlite_path,
  priv: storage_repo_priv,
  pool_size: 1,
  journal_mode: :wal,
  busy_timeout: 5_000

config :phoenix, :json_library, Jason

config :logger, :default_formatter, metadata: [:request_id]

config :symphony_elixir, SymphonyElixirWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: SymphonyElixirWeb.ErrorHTML, json: SymphonyElixirWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SymphonyElixir.PubSub,
  live_view: [signing_salt: "symphony-live-view"],
  secret_key_base: String.duplicate("s", 64),
  check_origin: false,
  server: false

import_config "#{config_env()}.exs"
