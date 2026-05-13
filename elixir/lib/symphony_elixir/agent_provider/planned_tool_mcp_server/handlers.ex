defmodule SymphonyElixir.AgentProvider.PlannedToolMcpServer.Handlers do
  @moduledoc false

  @spec source() :: String.t()
  def source do
    """
    async function handleMessage(message) {
      const id = message?.id ?? null;
      const method = message?.method;

      if (method === "initialize") {
        const protocolVersion =
          typeof message?.params?.protocolVersion === "string" && message.params.protocolVersion !== ""
            ? message.params.protocolVersion
            : "2024-11-05";

        sendResult(id, {
          protocolVersion,
          capabilities: { tools: {} },
          serverInfo: {
            name: "symphony-planned-tools",
            version: "0.1.0",
          },
        });
        return;
      }

      if (method === "notifications/initialized") {
        return;
      }

      if (method === "tools/list") {
        sendResult(id, { tools: TOOLS });
        return;
      }

      if (method === "tools/call") {
        const name = message?.params?.name;
        const tool = TOOLS.find((candidate) => candidate.name === name);

        if (!tool) {
          sendResult(
            id,
            failureResponse({
              error: {
                message: "Unsupported dynamic tool.",
                supportedTools: TOOLS.map((candidate) => candidate.name),
              },
            }),
          );
          return;
        }

        sendResult(id, await executeTool(name, message?.params?.arguments));
        return;
      }

      if (id !== null) {
        sendError(id, -32601, "Method not found", { method });
      }
    }
    """
  end
end
