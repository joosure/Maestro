defmodule SymphonyElixir.Storage.BoundaryTest do
  use ExUnit.Case, async: true

  @sqlite_path_env_pattern ~r/"(SYMPHONY_[A-Z0-9_]*SQLITE_PATH)"/
  @legacy_execution_plan_env_pattern ~r/SYMPHONY_EXECUTION_PLAN_(?:STORAGE_BACKEND|SQLITE_PATH)/
  @system_env_pattern ~r/System\.(?:get_env|fetch_env)\(/

  @domain_source_globs [
    "lib/symphony_elixir/agent/**/*.ex",
    "lib/symphony_elixir/orchestrator/**/*.ex",
    "lib/symphony_elixir/repo_provider/**/*.ex",
    "lib/symphony_elixir/tracker/**/*.ex",
    "lib/symphony_elixir/workflow/**/*.ex",
    "lib/symphony_elixir/workspace/**/*.ex"
  ]

  @domain_storage_config_globs [
    "lib/symphony_elixir/agent/**/storage/config.ex",
    "lib/symphony_elixir/orchestrator/**/storage/config.ex",
    "lib/symphony_elixir/repo_provider/**/storage/config.ex",
    "lib/symphony_elixir/tracker/**/storage/config.ex",
    "lib/symphony_elixir/workflow/**/storage/config.ex",
    "lib/symphony_elixir/workspace/**/storage/config.ex"
  ]

  @domain_storage_physical_patterns [
    {~r/\bdatabase:/, "database path config belongs to platform storage config"},
    {~r/priv\/storage_repo/, "Ecto migration priv path belongs to platform storage config"},
    {~r/\becto_repos:/, "Repo registration belongs to application/platform config"},
    {~r/SymphonyElixir\.Storage\.Migrator|Storage\.Migrator|Migrator\.migrate\(/, "migration runner belongs to application/platform startup"}
  ]

  @storage_domain_dependency_patterns [
    ~r/SymphonyElixir\.Agent\./,
    ~r/SymphonyElixir\.Workflow\./,
    ~r/SymphonyElixir\.Tracker\./,
    ~r/SymphonyElixir\.RepoProvider\./,
    ~r/SymphonyElixir\.Orchestrator\./,
    ~r/SymphonyWorkerDaemon\./
  ]

  test "SQLite path environment variables stay at the platform runtime config boundary" do
    offenders =
      elixir_config_and_source_files()
      |> matching_env_refs(@sqlite_path_env_pattern)
      |> Enum.reject(fn {file, env_name} ->
        file == "config/runtime.exs" and env_name == "SYMPHONY_STORAGE_SQLITE_PATH"
      end)

    assert offenders == [],
           "SQLite path env vars must stay platform-owned; offenders:\n#{format_offenders(offenders)}"
  end

  test "legacy execution-plan physical storage env vars are not referenced" do
    offenders =
      elixir_config_and_source_files()
      |> matching_files(@legacy_execution_plan_env_pattern)

    assert offenders == [],
           "execution-plan-specific physical storage env vars must not return; offenders:\n#{format_offenders(offenders)}"
  end

  test "domain storage config modules do not read OS environment directly" do
    offenders =
      source_files(@domain_storage_config_globs)
      |> matching_files(@system_env_pattern)

    assert offenders == [],
           "domain storage config modules must consume application config or typed opts, not System env; offenders:\n#{format_offenders(offenders)}"
  end

  test "domain source does not own physical database config or migrations" do
    offenders =
      for file <- source_files(@domain_source_globs),
          {pattern, reason} <- @domain_storage_physical_patterns,
          source = File.read!(file),
          Regex.match?(pattern, source) do
        {file, reason}
      end

    assert offenders == [],
           "physical storage config belongs to platform storage, not domain modules; offenders:\n#{format_offenders(offenders)}"
  end

  test "domain storage specs reference only platform SQLite env names" do
    offenders =
      domain_storage_spec_files()
      |> matching_env_refs(@sqlite_path_env_pattern)
      |> Enum.reject(fn {_file, env_name} -> env_name == "SYMPHONY_STORAGE_SQLITE_PATH" end)

    legacy_offenders =
      domain_storage_spec_files()
      |> matching_files(@legacy_execution_plan_env_pattern)

    assert offenders == [],
           "domain storage specs must not define subsystem-specific SQLite path env vars; offenders:\n#{format_offenders(offenders)}"

    assert legacy_offenders == [],
           "domain storage specs must not reference retired execution-plan physical storage env vars; offenders:\n#{format_offenders(legacy_offenders)}"
  end

  test "storage infrastructure does not compile-depend on concrete domains" do
    offenders =
      for file <- source_files(["lib/symphony_elixir/storage/**/*.ex"]),
          pattern <- @storage_domain_dependency_patterns,
          source = File.read!(file),
          Regex.match?(pattern, source) do
        {file, "storage infrastructure must not alias concrete domain modules"}
      end

    assert offenders == [],
           "Storage infrastructure must stay domain-neutral; offenders:\n#{format_offenders(offenders)}"
  end

  defp elixir_config_and_source_files do
    source_files(["config/*.exs", "lib/**/*.ex"])
  end

  defp domain_storage_spec_files do
    [
      "../specs/agent/execution_plan/**/*.md",
      "../specs/workflow/execution_plan_adoption/**/*.md"
    ]
    |> source_files()
  end

  defp source_files(globs) do
    globs
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.reject(&File.dir?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp matching_env_refs(files, pattern) do
    for file <- files,
        source = File.read!(file),
        [_match, env_name] <- Regex.scan(pattern, source) do
      {file, env_name}
    end
  end

  defp matching_files(files, pattern) do
    for file <- files,
        source = File.read!(file),
        Regex.match?(pattern, source) do
      file
    end
  end

  defp format_offenders([]), do: "(none)"

  defp format_offenders(offenders) do
    offenders
    |> Enum.map_join("\n", fn
      {file, detail} -> "- #{relative_path(file)}: #{detail}"
      file -> "- #{relative_path(file)}"
    end)
  end

  defp relative_path(path), do: Path.relative_to_cwd(path)
end
