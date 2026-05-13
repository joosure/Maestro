defmodule SymphonyElixir.AgentProvider.PlannedToolMcpServer.Template do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.BridgeContract

  alias SymphonyElixir.AgentProvider.PlannedToolMcpServer.{
    BridgeClient,
    Handlers,
    Protocol
  }

  @spec render(String.t()) :: String.t()
  def render(tools_json) when is_binary(tools_json) do
    """
    #!/usr/bin/env node
    const TOOLS = #{tools_json};
    const BASE_URL = process.env[#{inspect(BridgeContract.base_url_env())}];
    const TOKEN = process.env[#{inspect(BridgeContract.token_env())}];

    let buffer = "";
    let framing = "content-length";

    #{Protocol.source()}

    #{BridgeClient.source()}

    #{Handlers.source()}

    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      buffer += chunk;
      readMessages();
    });
    process.stdin.on("end", () => process.exit(0));
    process.stdin.resume();
    """
  end
end
