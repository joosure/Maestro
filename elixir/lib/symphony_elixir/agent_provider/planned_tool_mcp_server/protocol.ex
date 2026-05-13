defmodule SymphonyElixir.AgentProvider.PlannedToolMcpServer.Protocol do
  @moduledoc false

  @spec source() :: String.t()
  def source do
    """
    function send(message) {
      const payload = JSON.stringify(message);

      if (framing === "json-line") {
        process.stdout.write(`${payload}\\n`);
      } else {
        process.stdout.write(`Content-Length: ${Buffer.byteLength(payload, "utf8")}\\r\\n\\r\\n${payload}`);
      }
    }

    function sendResult(id, result) {
      send({ jsonrpc: "2.0", id, result });
    }

    function sendError(id, code, message, data) {
      send({ jsonrpc: "2.0", id, error: { code, message, data } });
    }

    function headerBoundary() {
      const crlf = buffer.indexOf("\\r\\n\\r\\n");

      if (crlf !== -1) {
        return { index: crlf, length: 4, separator: "\\r\\n" };
      }

      const lf = buffer.indexOf("\\n\\n");

      if (lf !== -1) {
        return { index: lf, length: 2, separator: "\\n" };
      }

      return null;
    }

    function readMessages() {
      while (true) {
        const boundary = headerBoundary();

        if (boundary === null) {
          if (buffer.toLowerCase().startsWith("content-length:")) {
            return;
          }

          const lineEnd = buffer.indexOf("\\n");

          if (lineEnd === -1) {
            return;
          }

          const line = buffer.slice(0, lineEnd).trim();
          buffer = buffer.slice(lineEnd + 1);

          if (line === "") {
            continue;
          }

          framing = "json-line";

          let message;

          try {
            message = JSON.parse(line);
          } catch (error) {
            sendError(null, -32700, "Parse error", { reason: String(error) });
            continue;
          }

          Promise.resolve(handleMessage(message)).catch((error) => {
            if (message?.id !== null && message?.id !== undefined) {
              sendError(message.id, -32603, "Internal error", { reason: String(error) });
            }
          });

          continue;
        }

        framing = "content-length";
        const header = buffer.slice(0, boundary.index);
        const contentLengthLine = header
          .split(boundary.separator)
          .find((line) => line.toLowerCase().startsWith("content-length:"));

        if (!contentLengthLine) {
          buffer = "";
          return;
        }

        const contentLength = Number(contentLengthLine.split(":")[1]?.trim() || "");

        if (!Number.isFinite(contentLength) || contentLength < 0) {
          buffer = "";
          return;
        }

        const bodyStart = boundary.index + boundary.length;

        if (buffer.length < bodyStart + contentLength) {
          return;
        }

        const body = buffer.slice(bodyStart, bodyStart + contentLength);
        buffer = buffer.slice(bodyStart + contentLength);

        let message;

        try {
          message = JSON.parse(body);
        } catch (error) {
          sendError(null, -32700, "Parse error", { reason: String(error) });
          continue;
        }

        Promise.resolve(handleMessage(message)).catch((error) => {
          if (message?.id !== null && message?.id !== undefined) {
            sendError(message.id, -32603, "Internal error", { reason: String(error) });
          }
        });
      }
    }
    """
  end
end
