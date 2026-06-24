defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.Support do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence

  @source_key Evidence.source_key()
  @status_key Evidence.status_key()
  @head_sha_key Evidence.head_sha_key()
  @published_head_sha_key Evidence.published_head_sha_key()
  @commits_key Evidence.commits_key()
  @url_key Evidence.url_key()
  @linked_to_tracker_key Evidence.linked_to_tracker_key()
  @observed_at_key Evidence.observed_at_key()
  @commands_key Evidence.commands_key()

  @spec observed(map() | term(), String.t()) :: [String.t()]
  def observed(value, prefix) when is_map(value) and map_size(value) > 0 do
    [
      if(present?(Map.get(value, @source_key)), do: "#{prefix}.#{@source_key}=#{Map.get(value, @source_key)}"),
      if(present?(Map.get(value, @status_key)), do: "#{prefix}.#{@status_key}=#{Map.get(value, @status_key)}"),
      if(present?(Map.get(value, @head_sha_key)), do: "#{prefix}.#{@head_sha_key}"),
      if(present?(Map.get(value, @url_key)), do: "#{prefix}.#{@url_key}"),
      if(Map.get(value, @linked_to_tracker_key) == true, do: "#{prefix}.#{@linked_to_tracker_key}")
    ]
    |> Enum.reject(&is_nil/1)
  end

  def observed(_value, _prefix), do: []

  @spec code_change_observed?(map()) :: boolean()
  def code_change_observed?(repo) when is_map(repo) do
    present?(Map.get(repo, @head_sha_key)) or
      present?(Map.get(repo, @published_head_sha_key)) or
      List.wrap(Map.get(repo, @commits_key)) != []
  end

  def code_change_observed?(_repo), do: false

  @spec current_head(map() | nil, map() | nil) :: term()
  def current_head(repo, change_proposal) do
    Map.get(repo || %{}, @published_head_sha_key) ||
      Map.get(repo || %{}, @head_sha_key) ||
      Map.get(change_proposal || %{}, @head_sha_key)
  end

  @spec stale_observation?(map() | term(), map() | nil, map() | nil) :: boolean()
  def stale_observation?(observation, repo, change_proposal) do
    observed_at = parsed_observed_at(observation)
    latest_head_observed_at = latest_observed_at([repo, change_proposal])

    case {observed_at, latest_head_observed_at} do
      {%DateTime{} = observed, %DateTime{} = latest} -> DateTime.compare(observed, latest) == :lt
      _timestamps -> false
    end
  end

  @spec latest_observed_at([term()]) :: DateTime.t() | nil
  def latest_observed_at(values) when is_list(values) do
    values
    |> Enum.flat_map(fn value ->
      case parsed_observed_at(value) do
        %DateTime{} = observed_at -> [observed_at]
        nil -> []
      end
    end)
    |> Enum.max_by(&DateTime.to_unix(&1, :microsecond), fn -> nil end)
  end

  @spec parsed_observed_at(term()) :: DateTime.t() | nil
  def parsed_observed_at(value) when is_map(value) do
    value
    |> Map.get(@observed_at_key)
    |> parse_datetime()
  end

  def parsed_observed_at(_value), do: nil

  @spec latest_command_head(map() | term()) :: term()
  def latest_command_head(validation) when is_map(validation) do
    validation
    |> Map.get(@commands_key, [])
    |> List.wrap()
    |> Enum.find_value(&Map.get(&1, @head_sha_key))
  end

  def latest_command_head(_validation), do: nil

  @spec stale_head?(term(), term()) :: boolean()
  def stale_head?(left, right), do: present?(left) and present?(right) and left != right

  @spec present?(term()) :: boolean()
  def present?(value) when is_binary(value), do: String.trim(value) != ""
  def present?(value), do: not is_nil(value)

  @spec integer(term(), integer()) :: integer()
  def integer(value, _default) when is_integer(value), do: value

  def integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _error -> default
    end
  end

  def integer(_value, default), do: default

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp parse_datetime(_value), do: nil
end
