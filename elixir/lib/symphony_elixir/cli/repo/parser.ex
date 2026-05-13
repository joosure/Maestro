defmodule SymphonyElixir.CLI.Repo.Parser do
  @moduledoc false

  @switches [
    path: :string,
    remote: :string,
    remote_url: :string,
    branch: :string,
    base: :string,
    work_prefix: :string,
    depth: :integer,
    message: :string,
    ff_only: :boolean,
    merge: :boolean,
    cached: :boolean,
    staged: :boolean,
    set_upstream: :boolean,
    force_with_lease: :boolean,
    help: :boolean
  ]

  @aliases [h: :help, m: :message]
  @read_only_commands ~w(root current-branch head-sha remote-url base-branch status preflight)
  @derived_read_commands ~w(working-branch)
  @branch_read_commands ~w(published-head-sha)
  @diff_read_commands ~w(diff)
  @check_read_commands ~w(diff-check)
  @write_commands ~w(clone fetch merge sync-base enable-rerere push delete-remote-branch create-branch create-working-branch switch-branch stage-all commit-all commit-staged)
  @commands @read_only_commands ++
              @derived_read_commands ++
              @branch_read_commands ++
              @diff_read_commands ++
              @check_read_commands ++
              @write_commands

  @type result ::
          {:ok, :help}
          | {:ok, String.t(), [String.t()], keyword()}
          | {:error, String.t()}

  @spec parse([String.t()]) :: result()
  def parse(argv) do
    case OptionParser.parse(argv, strict: @switches, aliases: @aliases) do
      {opts, [], []} ->
        if Keyword.get(opts, :help, false), do: {:ok, :help}, else: {:error, usage()}

      {opts, [command | args], []} when command in @commands ->
        if Keyword.get(opts, :help, false), do: {:ok, :help}, else: parse_command(command, args, opts)

      {_opts, [command | _args], []} ->
        {:error, "Unknown repo command: #{command}\n\n#{usage()}"}

      {_opts, _argv, invalid} when invalid != [] ->
        {:error, "Invalid repo option(s): #{inspect(invalid)}\n\n#{usage()}"}

      _other ->
        {:error, usage()}
    end
  end

  @spec usage() :: String.t()
  def usage do
    """
    Usage: symphony repo <command> [--path <path>] [--remote <name>]

    Commands:
      root
      current-branch
      head-sha
      published-head-sha <branch>
      remote-url
      base-branch
      working-branch <identifier> [--work-prefix <prefix>]
      status
      preflight [--remote-url <url>]
      diff [--merge] [--cached|--staged] [<ref-or-path> ...]
      diff-check [<ref-or-path> ...]
      clone <remote-url> <target-path> [--branch <branch>] [--depth <n>]
      fetch
      merge <ref> [--ff-only]
      sync-base [--base <branch>] [--ff-only]
      enable-rerere
      push <branch> [--set-upstream] [--force-with-lease]
      delete-remote-branch <branch>
      create-branch <branch> [--base <ref>]
      create-working-branch <identifier> [--base <ref>] [--work-prefix <prefix>]
      switch-branch <branch>
      stage-all
      commit-all --message <message>
      commit-staged --message <message>
    """
  end

  defp parse_command(command, [], opts) when command in @read_only_commands,
    do: {:ok, command, [], opts}

  defp parse_command(command, args, _opts) when command in @read_only_commands,
    do: {:error, "#{command} does not accept arguments: #{Enum.join(args, " ")}\n\n#{usage()}"}

  defp parse_command(command, args, opts) when command in @diff_read_commands,
    do: {:ok, command, args, opts}

  defp parse_command(command, args, opts) when command in @check_read_commands,
    do: {:ok, command, args, opts}

  defp parse_command("working-branch", [identifier], opts), do: {:ok, "working-branch", [identifier], opts}

  defp parse_command("working-branch", _args, _opts),
    do: {:error, "working-branch requires <identifier>\n\n#{usage()}"}

  defp parse_command(command, args, opts) when command in @branch_read_commands do
    case branch_arg(args, opts) do
      {:ok, branch} -> {:ok, command, [branch], opts}
      :error -> {:error, "#{command} requires <branch> or --branch <branch>\n\n#{usage()}"}
    end
  end

  defp parse_command("clone", [remote_url, target_path], opts),
    do: {:ok, "clone", [remote_url, target_path], opts}

  defp parse_command("clone", _args, _opts),
    do: {:error, "clone requires <remote-url> <target-path>\n\n#{usage()}"}

  defp parse_command("fetch", [], opts), do: {:ok, "fetch", [], opts}

  defp parse_command("fetch", args, _opts),
    do: {:error, "fetch does not accept arguments: #{Enum.join(args, " ")}\n\n#{usage()}"}

  defp parse_command("merge", [ref], opts), do: {:ok, "merge", [ref], opts}

  defp parse_command("merge", _args, _opts),
    do: {:error, "merge requires <ref>\n\n#{usage()}"}

  defp parse_command("sync-base", [], opts), do: {:ok, "sync-base", [], opts}

  defp parse_command("sync-base", args, _opts),
    do: {:error, "sync-base does not accept arguments: #{Enum.join(args, " ")}\n\n#{usage()}"}

  defp parse_command("enable-rerere", [], opts), do: {:ok, "enable-rerere", [], opts}

  defp parse_command("enable-rerere", args, _opts),
    do: {:error, "enable-rerere does not accept arguments: #{Enum.join(args, " ")}\n\n#{usage()}"}

  defp parse_command("push", args, opts) do
    case branch_arg(args, opts) do
      {:ok, branch} -> {:ok, "push", [branch], opts}
      :error -> {:error, "push requires <branch> or --branch <branch>\n\n#{usage()}"}
    end
  end

  defp parse_command("delete-remote-branch", args, opts) do
    case branch_arg(args, opts) do
      {:ok, branch} -> {:ok, "delete-remote-branch", [branch], opts}
      :error -> {:error, "delete-remote-branch requires <branch> or --branch <branch>\n\n#{usage()}"}
    end
  end

  defp parse_command("create-branch", args, opts) do
    case branch_arg(args, opts) do
      {:ok, branch} -> {:ok, "create-branch", [branch], opts}
      :error -> {:error, "create-branch requires <branch> or --branch <branch>\n\n#{usage()}"}
    end
  end

  defp parse_command("create-working-branch", [identifier], opts),
    do: {:ok, "create-working-branch", [identifier], opts}

  defp parse_command("create-working-branch", _args, _opts),
    do: {:error, "create-working-branch requires <identifier>\n\n#{usage()}"}

  defp parse_command("switch-branch", args, opts) do
    case branch_arg(args, opts) do
      {:ok, branch} -> {:ok, "switch-branch", [branch], opts}
      :error -> {:error, "switch-branch requires <branch> or --branch <branch>\n\n#{usage()}"}
    end
  end

  defp parse_command("stage-all", [], opts), do: {:ok, "stage-all", [], opts}

  defp parse_command("stage-all", args, _opts),
    do: {:error, "stage-all does not accept arguments: #{Enum.join(args, " ")}\n\n#{usage()}"}

  defp parse_command("commit-all", args, opts), do: {:ok, "commit-all", args, opts}
  defp parse_command("commit-staged", args, opts), do: {:ok, "commit-staged", args, opts}

  defp branch_arg([branch], _opts), do: present_branch(branch)
  defp branch_arg([], opts), do: opts |> Keyword.get(:branch) |> present_branch()
  defp branch_arg(_args, _opts), do: :error

  defp present_branch(value) do
    case present_string(value) do
      branch when is_binary(branch) -> {:ok, branch}
      nil -> :error
    end
  end

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      present -> present
    end
  end

  defp present_string(_value), do: nil
end
