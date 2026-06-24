defmodule SymphonyElixir.Storage.RepoTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Storage.Repo

  test "repo init creates parent directory for file-backed SQLite database" do
    root = Path.join(System.tmp_dir!(), "symphony-storage-repo-#{System.unique_integer([:positive])}")
    db_path = Path.join([root, "nested", "storage.db"])

    refute File.exists?(Path.dirname(db_path))

    assert {:ok, config} = Repo.init(:supervisor, database: db_path)
    assert config[:database] == db_path
    assert File.dir?(Path.dirname(db_path))

    File.rm_rf!(root)
  end

  test "repo init accepts in-memory SQLite database without filesystem setup" do
    assert {:ok, config} = Repo.init(:supervisor, database: ":memory:")
    assert config[:database] == ":memory:"
  end

  test "repo init accepts SQLite in-memory URI without filesystem setup" do
    database = "file::memory:?cache=shared"

    assert {:ok, config} = Repo.init(:supervisor, database: database)
    assert config[:database] == database
  end
end
