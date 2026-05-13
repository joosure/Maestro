defmodule SymphonyElixir.RepoProvider.CNB.Normalizer.Pull do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CNB.HttpClient
  alias SymphonyElixir.RepoProvider.CNB.Normalizer.Values

  @spec normalize_pull(map(), String.t(), map()) :: map()
  def normalize_pull(repo, repository, pull) do
    mergeable_state =
      pull
      |> Map.get("mergeable_state", pull[:mergeable_state] || "")
      |> to_string()
      |> String.downcase()

    blocked_on =
      pull |> Map.get("blocked_on", pull[:blocked_on] || "") |> to_string() |> String.downcase()

    state = normalized_pull_state(pull, mergeable_state)

    mergeable =
      cond do
        mergeable_state in ["conflict", "no-merge-base"] or blocked_on == "code_conflict" ->
          "CONFLICTING"

        mergeable_state in ["mergeable", "merged", "merging"] ->
          "MERGEABLE"

        true ->
          "UNKNOWN"
      end

    merge_state_status =
      cond do
        pull_wip?(pull) ->
          "DRAFT"

        mergeable_state in ["conflict", "no-merge-base"] ->
          "DIRTY"

        blocked_on in ["status_check", "waiting_review"] ->
          "BLOCKED"

        mergeable_state in ["mergeable", "merged", "merging"] ->
          "CLEAN"

        true ->
          "UNKNOWN"
      end

    %{
      "number" => Values.json_id(pull_number(pull)),
      "url" => HttpClient.pr_url(repo, repository, pull_number(pull)),
      "title" => pull_title(pull),
      "body" => pull_body(pull),
      "state" => state,
      "headRefName" => pull_head_branch(pull),
      "headRefOid" => pull_head_sha(pull),
      "baseRefName" => pull_base_branch(pull),
      "mergeable" => mergeable,
      "mergeStateStatus" => merge_state_status
    }
  end

  @spec normalized_pull_state(map(), String.t()) :: String.t()
  def normalized_pull_state(pull, mergeable_state) do
    raw_state = pull |> Map.get("state", pull[:state] || "") |> to_string() |> String.upcase()

    cond do
      raw_state == "MERGED" ->
        "MERGED"

      mergeable_state == "merged" ->
        "MERGED"

      raw_state == "CLOSED" and merged_by_present?(pull) ->
        "MERGED"

      true ->
        raw_state
    end
  end

  @spec merged_by_present?(map()) :: boolean()
  def merged_by_present?(pull) when is_map(pull) do
    case Map.get(pull, "merged_by", pull[:merged_by]) do
      merged_by when is_map(merged_by) ->
        Enum.any?(
          [
            {"id", :id},
            {"username", :username},
            {"nickname", :nickname},
            {"email", :email}
          ],
          fn {key, atom_key} ->
            case Values.field_value(merged_by, key, atom_key) do
              value when is_binary(value) -> value != ""
              value when is_integer(value) -> true
              _other -> false
            end
          end
        )

      _other ->
        false
    end
  end

  @spec pull_number(map()) :: term()
  def pull_number(%{"number" => number}), do: number
  def pull_number(%{number: number}), do: number
  def pull_number(_pull), do: nil

  @spec pull_title(map()) :: String.t()
  def pull_title(%{"title" => title}) when is_binary(title), do: title
  def pull_title(%{title: title}) when is_binary(title), do: title
  def pull_title(_pull), do: ""

  @spec pull_body(map()) :: String.t()
  def pull_body(%{"body" => body}) when is_binary(body), do: body
  def pull_body(%{body: body}) when is_binary(body), do: body
  def pull_body(_pull), do: ""

  @spec pull_head_branch(map()) :: String.t() | nil
  def pull_head_branch(%{"head" => %{"ref" => "refs/heads/" <> branch}}), do: branch
  def pull_head_branch(%{"head" => %{"ref" => ref}}) when is_binary(ref), do: ref
  def pull_head_branch(%{head: %{ref: "refs/heads/" <> branch}}), do: branch
  def pull_head_branch(%{head: %{ref: ref}}) when is_binary(ref), do: ref
  def pull_head_branch(_pull), do: nil

  @spec pull_head_sha(map()) :: String.t() | nil
  def pull_head_sha(%{"head" => %{"sha" => sha}}) when is_binary(sha), do: sha
  def pull_head_sha(%{head: %{sha: sha}}) when is_binary(sha), do: sha
  def pull_head_sha(_pull), do: nil

  @spec pull_base_branch(map()) :: String.t() | nil
  def pull_base_branch(%{"base" => %{"ref" => "refs/heads/" <> branch}}), do: branch
  def pull_base_branch(%{"base" => %{"ref" => ref}}) when is_binary(ref), do: ref
  def pull_base_branch(%{base: %{ref: "refs/heads/" <> branch}}), do: branch
  def pull_base_branch(%{base: %{ref: ref}}) when is_binary(ref), do: ref
  def pull_base_branch(_pull), do: nil

  @spec pull_wip?(map()) :: boolean()
  def pull_wip?(%{"is_wip" => value}), do: value in [true, "true"]
  def pull_wip?(%{is_wip: value}), do: value in [true, "true"]
  def pull_wip?(_pull), do: false

  @spec pull_state_priority(map()) :: non_neg_integer()
  def pull_state_priority(pull) when is_map(pull) do
    case pull |> Map.get("state", pull[:state] || "") |> to_string() |> String.downcase() do
      "open" -> 0
      "merged" -> 1
      "closed" -> 2
      _other -> 3
    end
  end

  def pull_state_priority(_pull), do: 3

  @spec pull_head_ref(map()) :: String.t() | nil
  def pull_head_ref(%{"head" => %{"ref" => ref}}) when is_binary(ref), do: ref
  def pull_head_ref(%{head: %{ref: ref}}) when is_binary(ref), do: ref
  def pull_head_ref(_pull), do: nil
end
