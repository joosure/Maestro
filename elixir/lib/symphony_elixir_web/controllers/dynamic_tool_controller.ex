defmodule SymphonyElixirWeb.DynamicToolController do
  @moduledoc """
  HTTP entrypoint used by external agent-provider helper processes to execute
  agent dynamic tools through Symphony.
  """

  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias SymphonyElixir.Agent.DynamicTool.Bridge

  @spec execute(Conn.t(), map()) :: Conn.t()
  def execute(conn, %{"tool" => tool} = params) when is_binary(tool) do
    with :ok <- authorize_loopback(conn),
         {:ok, token} <- authorize_token(conn) do
      arguments = Map.get(params, "arguments", %{})
      opts = params |> Map.get("context") |> request_context_opts() |> Bridge.put_token_context(token)
      json(conn, Bridge.execute(tool, arguments, opts))
    else
      {:error, :forbidden_remote_address} ->
        conn
        |> put_status(403)
        |> json(%{"success" => false, "payload" => %{"error" => %{"message" => "Dynamic tool bridge requests are restricted to loopback clients."}}})

      {:error, :unauthorized} ->
        conn
        |> put_status(401)
        |> json(%{"success" => false, "payload" => %{"error" => %{"message" => "Unauthorized dynamic tool bridge request."}}})
    end
  end

  def execute(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{
      "success" => false,
      "payload" => %{"error" => %{"message" => "Dynamic tool bridge requests require a non-empty tool name."}}
    })
  end

  defp authorize_loopback(%Conn{remote_ip: {127, _a, _b, _c}}), do: :ok
  defp authorize_loopback(%Conn{remote_ip: {0, 0, 0, 0, 0, 0, 0, 1}}), do: :ok
  defp authorize_loopback(_conn), do: {:error, :forbidden_remote_address}

  defp authorize_token(conn) do
    conn
    |> get_req_header("authorization")
    |> bearer_token()
    |> case do
      token when is_binary(token) ->
        if Bridge.valid_token?(token), do: {:ok, token}, else: {:error, :unauthorized}

      _token ->
        {:error, :unauthorized}
    end
  end

  defp bearer_token(["Bearer " <> token | _headers]), do: token
  defp bearer_token(["bearer " <> token | _headers]), do: token
  defp bearer_token(_headers), do: nil

  defp request_context_opts(%{"workspace" => workspace}) when is_binary(workspace) do
    case String.trim(workspace) do
      "" -> []
      normalized -> [workspace: normalized]
    end
  end

  defp request_context_opts(_context), do: []
end
