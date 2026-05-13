defmodule SymphonyElixir.AgentProvider.PlannedToolMcpServer.BridgeClient do
  @moduledoc false

  @spec source() :: String.t()
  def source do
    """
    function format(value) {
      return JSON.stringify(value, null, 2);
    }

    function successResponse(payload) {
      return { content: [{ type: "text", text: format(payload) }], isError: false };
    }

    function failureResponse(payload) {
      return { content: [{ type: "text", text: format(payload) }], isError: true };
    }

    function bridgeUnavailableResponse() {
      return failureResponse({
        error: {
            message: "Symphony Dynamic Tool bridge is unavailable for this provider process.",
        },
      });
    }

    async function readJson(response) {
      try {
        return await response.json();
      } catch (error) {
        return {
          success: false,
          payload: {
            error: {
              message: "Symphony Dynamic Tool bridge returned a non-JSON response.",
              reason: error instanceof Error ? error.message : String(error),
            },
          },
        };
      }
    }

    async function executeTool(name, args) {
      if (!BASE_URL || !TOKEN) {
        return bridgeUnavailableResponse();
      }

      try {
        const response = await fetch(`${BASE_URL}/execute`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${TOKEN}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            tool: name,
            arguments: args ?? {},
            context: {
              workspace: process.cwd(),
            },
          }),
        });

        const payload = await readJson(response);

        if (!response.ok || payload?.success === false) {
          return failureResponse(payload?.payload ?? payload);
        }

        return successResponse(payload?.payload ?? payload);
      } catch (error) {
        return failureResponse({
          error: {
            message: "Symphony Dynamic Tool bridge request failed.",
            reason: error instanceof Error ? error.message : String(error),
          },
        });
      }
    }
    """
  end
end
