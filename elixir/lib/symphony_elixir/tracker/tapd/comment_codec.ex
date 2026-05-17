defmodule SymphonyElixir.Tracker.Tapd.CommentCodec do
  @moduledoc false

  alias SymphonyElixir.Tracker.Tapd.CommentCodec.{
    DescriptionDecoder,
    DescriptionEncoder,
    ResponseNormalizer
  }

  alias SymphonyElixir.Tracker.Tapd.Client.Paths

  @comments_path Paths.comments()

  @spec normalize_request_params(String.t(), String.t(), map()) :: map()
  def normalize_request_params("POST", @comments_path, %{"description" => description} = params)
      when is_binary(description) do
    Map.put(params, "description", encode_description(description))
  end

  def normalize_request_params(_method, _path, params) when is_map(params), do: params

  @spec normalize_response_body(String.t(), String.t(), term()) :: term()
  def normalize_response_body(_method, @comments_path, body), do: ResponseNormalizer.normalize(body)

  def normalize_response_body(_method, _path, body), do: body

  @spec encode_description(String.t()) :: String.t()
  def encode_description(description) when is_binary(description), do: DescriptionEncoder.encode(description)

  @spec decode_description(String.t()) :: String.t()
  def decode_description(description) when is_binary(description), do: DescriptionDecoder.decode(description)
end
