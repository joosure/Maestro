import Config

config :symphony_elixir, :storage, backend: :memory

config :symphony_elixir, :agent_execution_plan, storage: :memory

config :symphony_elixir, :workflow_execution_plan_adoption, storage: :memory
