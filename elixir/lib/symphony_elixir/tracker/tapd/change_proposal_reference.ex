defmodule SymphonyElixir.Tracker.Tapd.ChangeProposalReference do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker.ChangeProposalReference
  alias SymphonyElixir.Tracker.Tapd.Client.{Fields, Paths, Request, Response}

  @default_comment_limit 50

  @spec fetch(map(), Issue.t() | map(), keyword()) ::
          {:ok, ChangeProposalReference.t() | nil} | {:error, term()}
  def fetch(tracker, issue, opts \\ [])

  def fetch(tracker, %Issue{id: issue_id}, opts)
      when is_map(tracker) and is_binary(issue_id) and is_list(opts) do
    fetch_from_comments(tracker, issue_id, opts)
  end

  def fetch(_tracker, _issue, _opts), do: {:ok, nil}

  defp fetch_from_comments(tracker, issue_id, opts) do
    params = %{
      "entry_type" => "stories",
      "entry_id" => issue_id,
      "order" => "created desc",
      "limit" => comment_limit(opts)
    }

    request_opts =
      opts
      |> Keyword.take([:request_fun, :retry_delays_ms, :sleep_fun])
      |> Keyword.put(:tracker, tracker)
      |> Keyword.put(:operation, :fetch_change_proposal_reference)

    with {:ok, body} <- Request.request("GET", Paths.comments(), params, request_opts),
         {:ok, comments} <- comments_from_body(body) do
      {:ok, Enum.find_value(comments, &reference_from_comment/1)}
    end
  end

  defp comments_from_body(body) do
    with {:ok, data} <- Response.decode_success_envelope(Paths.comments(), body),
         true <- is_list(data) || {:error, {:unexpected_tapd_payload, Paths.comments(), body}} do
      {:ok, Enum.flat_map(data, &normalize_comment/1)}
    end
  end

  defp normalize_comment(%{"Comment" => %{} = comment}), do: [Fields.normalize_keys_to_strings(comment)]
  defp normalize_comment(%{Comment: %{} = comment}), do: [Fields.normalize_keys_to_strings(comment)]
  defp normalize_comment(%{} = comment), do: [Fields.normalize_keys_to_strings(comment)]
  defp normalize_comment(_comment), do: []

  defp reference_from_comment(comment) when is_map(comment) do
    comment
    |> Fields.string_field("description")
    |> reference_from_body()
  end

  defp reference_from_body(body) when is_binary(body) do
    body
    |> change_proposal_section()
    |> reference_from_section()
  end

  defp reference_from_body(_body), do: nil

  defp change_proposal_section(body) do
    lines = String.split(body, "\n")

    case Enum.find_index(lines, &change_proposal_heading?/1) do
      nil ->
        nil

      index ->
        lines
        |> Enum.drop(index + 1)
        |> Enum.take_while(&(not markdown_heading?(&1)))
        |> Enum.join("\n")
    end
  end

  defp reference_from_section(nil), do: nil

  defp reference_from_section(section) when is_binary(section) do
    with url when is_binary(url) <- first_url(section) do
      %ChangeProposalReference{url: url, number: number_from_url(url)}
    end
  end

  defp first_url(section) do
    markdown_url(section) || raw_change_proposal_url(section)
  end

  defp markdown_url(section) do
    case Regex.run(~r/\[[^\]]+\]\((https?:\/\/[^)\s]+)\)/, section, capture: :all_but_first) do
      [url] -> url
      _match -> nil
    end
  end

  defp raw_change_proposal_url(section) do
    case Regex.run(~r{https?://[^\s)]+/(?:-/)?(?:pulls|pull|merge_requests)/\d+}, section) do
      [url] -> url
      _match -> nil
    end
  end

  defp number_from_url(url) when is_binary(url) do
    url
    |> URI.parse()
    |> Map.get(:path)
    |> number_from_path()
  end

  defp number_from_path(path) when is_binary(path) do
    segments = String.split(path, "/", trim: true)

    Enum.find_value(Enum.with_index(segments), fn
      {"pulls", index} -> Enum.at(segments, index + 1)
      {"pull", index} -> Enum.at(segments, index + 1)
      {"merge_requests", index} -> Enum.at(segments, index + 1)
      _segment -> nil
    end)
  end

  defp number_from_path(_path), do: nil

  defp change_proposal_heading?(line) when is_binary(line) do
    Regex.match?(~r/^\#{1,6}\s+Change Proposal\s*$/i, String.trim(line))
  end

  defp markdown_heading?(line) when is_binary(line) do
    Regex.match?(~r/^\#{1,6}\s+\S+/, String.trim(line))
  end

  defp comment_limit(opts) do
    case Keyword.get(opts, :comment_limit, @default_comment_limit) do
      value when is_integer(value) and value > 0 -> value
      _value -> @default_comment_limit
    end
  end
end
