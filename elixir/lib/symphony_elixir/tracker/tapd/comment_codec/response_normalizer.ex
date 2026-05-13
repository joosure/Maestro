defmodule SymphonyElixir.Tracker.Tapd.CommentCodec.ResponseNormalizer do
  @moduledoc false

  alias SymphonyElixir.Tracker.Tapd.CommentCodec.DescriptionDecoder

  @spec normalize(term()) :: term()
  def normalize(body) do
    update_tapd_data(body, &normalize_comments_data/1)
  end

  defp update_tapd_data(%{"data" => data} = body, fun) when is_function(fun, 1),
    do: Map.put(body, "data", fun.(data))

  defp update_tapd_data(%{data: data} = body, fun) when is_function(fun, 1),
    do: Map.put(body, :data, fun.(data))

  defp update_tapd_data(body, _fun), do: body

  defp normalize_comments_data(data) when is_list(data), do: Enum.map(data, &normalize_comment_entry/1)
  defp normalize_comments_data(%{} = data), do: normalize_comment_entry(data)
  defp normalize_comments_data(data), do: data

  defp normalize_comment_entry(%{"Comment" => %{} = _comment} = entry) do
    put_in(entry, ["Comment"], normalize_comment(entry["Comment"]))
  end

  defp normalize_comment_entry(%{Comment: %{} = comment} = entry) do
    %{entry | Comment: normalize_comment(comment)}
  end

  defp normalize_comment_entry(%{} = comment), do: normalize_comment(comment)
  defp normalize_comment_entry(entry), do: entry

  defp normalize_comment(%{"description" => description} = comment) when is_binary(description),
    do: Map.put(comment, "description", DescriptionDecoder.decode(description))

  defp normalize_comment(%{description: description} = comment) when is_binary(description),
    do: %{comment | description: DescriptionDecoder.decode(description)}

  defp normalize_comment(comment), do: comment
end
