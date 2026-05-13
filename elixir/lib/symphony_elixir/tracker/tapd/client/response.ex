defmodule SymphonyElixir.Tracker.Tapd.Client.Response do
  @moduledoc false

  alias SymphonyElixir.Tracker.Error

  @spec tapd_success?(term()) :: boolean()
  def tapd_success?(%{"status" => status}) when status in [1, "1"], do: true
  def tapd_success?(%{status: status}) when status in [1, "1"], do: true
  def tapd_success?(_body), do: false

  @spec decode_success_envelope(String.t(), term()) :: {:ok, term()} | {:error, term()}
  def decode_success_envelope(path, body) when is_binary(path) do
    cond do
      not tapd_success?(body) ->
        {:error, {:unexpected_tapd_payload, path, body}}

      is_map(body) and Map.has_key?(body, "data") ->
        {:ok, body["data"]}

      is_map(body) and Map.has_key?(body, :data) ->
        {:ok, body.data}

      true ->
        {:error, {:unexpected_tapd_payload, path, body}}
    end
  end

  @spec tapd_error_reason(term()) :: term()
  def tapd_error_reason(%{status: 200, body: body}), do: {:tapd_business_error, body}
  def tapd_error_reason(%{"status" => 200, "body" => body}), do: {:tapd_business_error, body}
  def tapd_error_reason(%{status: status, body: body}), do: {:tapd_http_status, status, body}

  def tapd_error_reason(%{"status" => status, "body" => body}),
    do: {:tapd_http_status, status, body}

  def tapd_error_reason(reason), do: {:tapd_request, reason}

  @spec handle_response(term()) :: {:ok, map()} | {:error, term()}
  def handle_response({:ok, response}), do: handle_response(response)
  def handle_response({:error, reason}), do: {:error, {:tapd_request, reason}}

  def handle_response(%Req.Response{status: 200, body: body}) do
    if tapd_success?(body) do
      {:ok, body}
    else
      {:error, {:tapd_business_error, body}}
    end
  end

  def handle_response(%Req.Response{status: status, body: body}) do
    {:error, {:tapd_http_status, status, body}}
  end

  def handle_response(%{status: 200, body: body}) do
    if tapd_success?(body) do
      {:ok, body}
    else
      {:error, {:tapd_business_error, body}}
    end
  end

  def handle_response(%{status: status, body: body}) do
    {:error, {:tapd_http_status, status, body}}
  end

  def handle_response(other), do: {:error, {:tapd_request, other}}

  @spec response_status(term()) :: integer() | nil
  def response_status({:ok, response}), do: response_status(response)
  def response_status(%Req.Response{status: status}), do: status
  def response_status(%{status: status}), do: status
  def response_status(_response), do: nil

  @spec error_status(term()) :: integer() | nil
  def error_status(%Error{code: :http_status, details: %{status: status}}), do: status
  def error_status(%Error{code: :business_error}), do: 200
  def error_status({:tapd_http_status, status, _body}), do: status
  def error_status({:tapd_business_error, _body}), do: 200
  def error_status(_reason), do: nil
end
