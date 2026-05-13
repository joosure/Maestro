defmodule SymphonyElixir.RepoProvider.CNB.Normalizer.Errors do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Error

  @spec map_runtime_error(term()) :: Error.t()
  def map_runtime_error({:cnb_api_status, method, url, 403, body})
      when is_binary(url) and is_map(body) do
    if cnb_build_scope_error?(url, body) do
      Error.runtime_failure(
        :cnb_build_scope_required,
        "CNB build endpoints require build/bill authorization for this repository; current CNB_TOKEN cannot access run data. Grant CNB build authorization for the target repository and retry.",
        body
      )
    else
      Error.runtime_failure(
        :cnb_api_status,
        "CNB API #{String.upcase(to_string(method))} #{url} failed: HTTP 403: #{Jason.encode!(body)}",
        body
      )
    end
  end

  def map_runtime_error({:cnb_api_status, method, url, status, body}) do
    Error.runtime_failure(
      :cnb_api_status,
      "CNB API #{String.upcase(to_string(method))} #{url} failed: HTTP #{status}: #{Jason.encode!(body)}",
      body
    )
  end

  def map_runtime_error({:cnb_api_request, method, url, reason}) do
    Error.runtime_failure(
      :cnb_api_request,
      "CNB API #{String.upcase(to_string(method))} #{url} failed: #{inspect(reason)}",
      reason
    )
  end

  def map_runtime_error({:cnb_unknown_payload, action, payload}) do
    Error.runtime_failure(
      :cnb_unknown_payload,
      "Unexpected CNB payload for #{action}: #{Jason.encode!(payload)}",
      payload
    )
  end

  def map_runtime_error({:cnb_pull_not_found, branch}) do
    Error.runtime_failure(
      :cnb_pull_not_found,
      "Unable to find an open CNB pull request for branch #{branch}"
    )
  end

  def map_runtime_error({:cnb_pull_not_found_for_branch, branch}) do
    Error.runtime_failure(
      :cnb_pull_not_found,
      "No CNB pull request found for branch #{branch}"
    )
  end

  def map_runtime_error({:cnb_pull_not_found_for_sha, sha}) do
    Error.runtime_failure(
      :cnb_pull_not_found,
      "No CNB pull request found for head sha #{sha}"
    )
  end

  def map_runtime_error({:cnb_invalid_pull_target, target}) do
    Error.runtime_failure(
      :cnb_invalid_pull_target,
      "Invalid CNB pull request target #{inspect(target)}"
    )
  end

  def map_runtime_error({:cnb_pull_target_repository_mismatch, target, expected, actual}) do
    Error.runtime_failure(
      :cnb_pull_target_repository_mismatch,
      "CNB pull request URL #{target} belongs to repository #{actual}, expected #{expected}",
      %{target: target, expected_repository: expected, actual_repository: actual}
    )
  end

  def map_runtime_error({:cnb_run_not_found, run_id}) do
    Error.runtime_failure(
      :cnb_run_not_found,
      "No CNB run found for id #{run_id}"
    )
  end

  def map_runtime_error(:cnb_current_branch_unavailable) do
    Error.runtime_failure(
      :cnb_current_branch_unavailable,
      "Unable to determine the current git branch"
    )
  end

  def map_runtime_error(:cnb_run_id_required) do
    Error.runtime_failure(:cnb_run_id_required, "CNB run-view requires a run id")
  end

  def map_runtime_error(:missing_cnb_token) do
    Error.runtime_failure(:missing_cnb_token, "CNB provider requires CNB_TOKEN")
  end

  def map_runtime_error(:missing_cnb_repository_slug) do
    Error.runtime_failure(:missing_cnb_repository_slug, "CNB provider requires a repository slug")
  end

  def map_runtime_error(other) do
    Error.runtime_failure(:cnb_runtime_failure, inspect(other), other)
  end

  @spec cnb_build_scope_error?(String.t(), map()) :: boolean()
  def cnb_build_scope_error?(url, body) do
    String.contains?(url, "/-/build/") and
      (Map.get(body, "errcode") == 7 or
         String.contains?(
           body |> Map.get("errmsg", "") |> to_string() |> String.downcase(),
           "bill authorization scope"
         ))
  end
end
