defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.IssueKeys do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceStore
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.Normalization

  @run_id_key "run_id"
  @issue_id_key "issue_id"
  @issue_identifier_key "issue_identifier"
  @runtime_metadata_key "runtime_metadata"

  @spec issue_keys(term(), keyword()) :: [String.t()]
  def issue_keys(arguments, opts) do
    runtime_metadata = opts |> Keyword.get(:tool_context) |> runtime_metadata()
    run_id = Keyword.get(opts, :run_id) || Map.get(runtime_metadata, :run_id) || Map.get(runtime_metadata, @run_id_key)

    issue_keys =
      [
        Normalization.value(arguments, @issue_id_key),
        Normalization.value(arguments, @issue_identifier_key),
        Keyword.get(opts, :issue_id),
        Keyword.get(opts, :issue_identifier),
        Map.get(runtime_metadata, :issue_id),
        Map.get(runtime_metadata, @issue_id_key),
        Map.get(runtime_metadata, :issue_identifier),
        Map.get(runtime_metadata, @issue_identifier_key)
      ]
      |> Enum.flat_map(&Normalization.present_values/1)
      |> Enum.uniq()

    (issue_keys ++ EvidenceStore.scope_issue_keys(run_id, issue_keys, opts))
    |> Enum.uniq()
  end

  defp runtime_metadata(%{runtime_metadata: metadata}) when is_map(metadata), do: metadata
  defp runtime_metadata(%{@runtime_metadata_key => metadata}) when is_map(metadata), do: metadata
  defp runtime_metadata(_context), do: %{}
end
