defmodule SymphonyElixir.AgentProvider.ClaudeCode.Tooling.RemoteBootstrap do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.ClaudeCode.Tooling.McpConfig
  alias SymphonyElixir.AgentProvider.PlannedToolMcpServer

  @git_exclude_entry ".symphony/"

  @spec script(Path.t(), [map()]) :: String.t()
  def script(workspace, tool_specs) when is_binary(workspace) and is_list(tool_specs) do
    [
      "set -eu",
      shell_assign("workspace", workspace),
      base64_writer(),
      "config_dir=\"$workspace/#{McpConfig.bundle_relative_path()}\"",
      "config_path=\"$workspace/#{McpConfig.relative_path()}\"",
      "server_path=\"$workspace/#{McpConfig.server_relative_path()}\"",
      "mkdir -p \"$config_dir\"",
      write_base64_file_command("$config_path", McpConfig.source(tool_specs)),
      server_script(tool_specs),
      git_exclude_script()
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp server_script([_tool_spec | _] = tool_specs) do
    [
      "command -v node >/dev/null 2>&1 || { echo 'node is required for Claude Code Dynamic Tool MCP tooling' >&2; exit 127; }",
      write_base64_file_command("$server_path", PlannedToolMcpServer.source(tool_specs)),
      "chmod 755 \"$server_path\""
    ]
  end

  defp server_script(_tool_specs), do: ["rm -f \"$server_path\""]

  defp base64_writer do
    """
    write_base64_file() {
      target_path="$1"
      payload="$2"

      if command -v base64 >/dev/null 2>&1; then
        if printf '%s' "$payload" | base64 --decode > "$target_path" 2>/dev/null; then
          return 0
        fi

        if printf '%s' "$payload" | base64 -d > "$target_path" 2>/dev/null; then
          return 0
        fi

        if printf '%s' "$payload" | base64 -D > "$target_path" 2>/dev/null; then
          return 0
        fi
      fi

      if command -v openssl >/dev/null 2>&1; then
        printf '%s' "$payload" | openssl base64 -d -A > "$target_path"
        return $?
      fi

      echo 'base64 decoder is required for Claude Code Dynamic Tool MCP tooling' >&2
      return 127
    }
    """
    |> String.trim()
  end

  defp write_base64_file_command(target, source) when is_binary(target) and is_binary(source) do
    "write_base64_file #{target} #{shell_escape(Base.encode64(source))}"
  end

  defp git_exclude_script do
    [
      "if command -v git >/dev/null 2>&1; then",
      "  exclude_path=$(cd \"$workspace\" && git rev-parse --git-path info/exclude 2>/dev/null || true)",
      "  if [ -n \"$exclude_path\" ]; then",
      "    case \"$exclude_path\" in",
      "      /*) final_exclude_path=\"$exclude_path\" ;;",
      "      *) final_exclude_path=\"$workspace/$exclude_path\" ;;",
      "    esac",
      "    mkdir -p \"$(dirname \"$final_exclude_path\")\"",
      "    touch \"$final_exclude_path\"",
      "    if ! grep -Fqx #{shell_escape(@git_exclude_entry)} \"$final_exclude_path\"; then",
      "      printf '%s\\n' #{shell_escape(@git_exclude_entry)} >> \"$final_exclude_path\"",
      "    fi",
      "  fi",
      "fi"
    ]
  end

  defp shell_assign(name, value) when is_binary(name) and is_binary(value) do
    "#{name}=#{shell_escape(value)}"
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end
end
