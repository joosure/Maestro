defmodule SymphonyElixir.AgentProvider.Codex.Tooling.WrapperSource do
  @moduledoc false

  @env_name_pattern ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  @spec source(map()) :: String.t()
  def source(env) when is_map(env) do
    [
      "#!/bin/sh",
      "set -eu",
      "script_dir=$(CDPATH= cd \"$(dirname \"$0\")\" && pwd)",
      env_exports(env),
      "exec node \"$script_dir/planned_tools_mcp.js\""
    ]
    |> List.flatten()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp env_exports(env) when is_map(env) do
    env
    |> Enum.flat_map(fn
      {key, value} when is_binary(key) and is_binary(value) and value != "" ->
        if Regex.match?(@env_name_pattern, key) do
          ["if [ -z \"${#{key}:-}\" ]; then", "  #{key}=#{shell_escape(value)}", "  export #{key}", "fi"]
        else
          []
        end

      _entry ->
        []
    end)
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end
end
