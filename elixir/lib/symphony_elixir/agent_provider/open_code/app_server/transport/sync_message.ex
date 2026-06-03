defmodule SymphonyElixir.AgentProvider.OpenCode.AppServer.Transport.SyncMessage do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.OpenCode.AppServer.{Context, Diagnostics, Paths}

  @spec run(map(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def run(session, prompt, message_id) when is_map(session) and is_binary(prompt) and is_binary(message_id) do
    path = Paths.session_message(session.session_id)
    payload = payload(session, prompt, message_id)
    context = context(session, prompt, message_id)

    case Req.post(session.request, url: path, json: payload, receive_timeout: session.settings.turn_timeout_ms) do
      {:ok, %{status: status, body: %{} = body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:error, response_contract_error(path, status, body, context)}

      {:ok, %{status: status, body: body}} ->
        {:error, request_http_error(:turn_message_http_error, "POST", path, status, body, context)}

      {:error, reason} ->
        {:error, request_transport_error(:turn_message_transport_error, "POST", path, reason, context)}
    end
  end

  defp payload(session, prompt, message_id) do
    %{
      "messageID" => message_id,
      "agent" => session.settings.agent,
      "parts" => [
        %{
          "type" => "text",
          "text" => prompt
        }
      ]
    }
    |> maybe_put_model(session.settings.model)
    |> maybe_put_variant(session.settings.variant)
  end

  defp context(session, prompt, message_id) do
    session
    |> Context.session()
    |> Map.merge(%{
      prompt_bytes: byte_size(prompt),
      message_id: message_id
    })
  end

  defp maybe_put_model(payload, model) when is_binary(model) do
    case String.split(model, "/", parts: 2) do
      [provider_id, model_id] when provider_id != "" and model_id != "" ->
        Map.put(payload, "model", %{"providerID" => provider_id, "modelID" => model_id})

      _parts ->
        payload
    end
  end

  defp maybe_put_model(payload, _model), do: payload

  defp maybe_put_variant(payload, variant) when is_binary(variant), do: Map.put(payload, "variant", variant)
  defp maybe_put_variant(payload, _variant), do: payload

  defp response_contract_error(path, status, body, context) do
    {:turn_message_response_error,
     Map.merge(context, %{
       method: "POST",
       path: path,
       response_status: status,
       response_body: Diagnostics.preview_value(body),
       message: "OpenCode returned a successful POST #{path} response without a message object"
     })}
  end

  defp request_http_error(kind, method, path, status, body, context) do
    {kind,
     Map.merge(context, %{
       method: method,
       path: path,
       response_status: status,
       response_body: Diagnostics.preview_value(body),
       message: "OpenCode returned HTTP #{status} for #{method} #{path}"
     })}
  end

  defp request_transport_error(kind, method, path, reason, context) do
    transport_reason = req_transport_reason(reason)

    message =
      if transport_reason == :timeout,
        do: "OpenCode did not return #{method} #{path} before turn_timeout_ms elapsed",
        else: "OpenCode request failed for #{method} #{path}"

    {kind,
     Map.merge(context, %{
       method: method,
       path: path,
       transport_reason: transport_reason,
       cause: Diagnostics.preview_value(reason),
       message: message
     })}
  end

  defp req_transport_reason(%Req.TransportError{reason: reason}), do: reason
  defp req_transport_reason(_reason), do: nil
end
