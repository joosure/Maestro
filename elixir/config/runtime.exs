import Config

storage_backend_env = "SYMPHONY_STORAGE_BACKEND"
storage_sqlite_path_env = "SYMPHONY_STORAGE_SQLITE_PATH"

if backend = System.get_env(storage_backend_env) do
  config :symphony_elixir, :storage, backend: backend
end

if sqlite_path = System.get_env(storage_sqlite_path_env) do
  config :symphony_elixir, SymphonyElixir.Storage.Repo, database: sqlite_path
end
