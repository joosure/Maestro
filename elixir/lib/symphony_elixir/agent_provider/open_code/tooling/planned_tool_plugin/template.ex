defmodule SymphonyElixir.AgentProvider.OpenCode.Tooling.PlannedToolPlugin.Template do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.BridgeContract

  @spec render(%{tool_name: String.t(), description: String.t(), args_source: String.t()}) :: String.t()
  def render(%{tool_name: tool_name, description: description, args_source: args_source})
      when is_binary(tool_name) and is_binary(description) and is_binary(args_source) do
    """
    import { tool } from "@opencode-ai/plugin";
    import { z } from "zod";

    const TOOL_NAME = #{inspect(tool_name)};
    const BASE_URL = process.env[#{inspect(BridgeContract.base_url_env())}];
    const TOKEN = process.env[#{inspect(BridgeContract.token_env())}];

    const format = (value: unknown) => JSON.stringify(value, null, 2);

    const fail = (payload: unknown): never => {
      throw new Error(format(payload));
    };

    const readJson = async (response: Response) => {
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
    };

    export default tool({
      description: #{inspect(description)},
      args: {
    #{args_source}
      },
      async execute(args) {
        if (!BASE_URL || !TOKEN) {
          fail({
            error: {
              message: "Symphony Dynamic Tool bridge is unavailable for this provider process.",
            },
          });
        }

        let response: Response;
        let payload: any;

        try {
          response = await fetch(`${BASE_URL}/execute`, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${TOKEN}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              tool: TOOL_NAME,
              arguments: args ?? {},
              context: {
                workspace: process.cwd(),
              },
            }),
          });

          payload = await readJson(response);
        } catch (error) {
          fail({
            error: {
              message: "Symphony Dynamic Tool bridge request failed.",
              reason: error instanceof Error ? error.message : String(error),
            },
          });
        }

        if (!response.ok || payload?.success === false) {
          fail(payload?.payload ?? payload);
        }

        return format(payload?.payload ?? payload);
      },
    });
    """
  end
end
