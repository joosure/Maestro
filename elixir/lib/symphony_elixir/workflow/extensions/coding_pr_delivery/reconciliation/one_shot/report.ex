defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Report do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Smoke.ResultStatus
  alias SymphonyElixir.Storage.Scrubber
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Tracker.ProjectRef
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config, as: ReconciliationConfig
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Fields

  @type probe_result :: %{
          id: String.t(),
          ok: boolean(),
          duration_ms: non_neg_integer(),
          summary: String.t(),
          error: String.t() | nil
        }

  @type t :: %{
          workflow: String.t() | nil,
          issue_id: String.t() | nil,
          tracker_kind: String.t() | nil,
          repo_provider_kind: String.t() | nil,
          project_id: String.t() | nil,
          project_url: String.t() | nil,
          candidate_discovery: String.t() | nil,
          mode: String.t(),
          shadow: map() | nil,
          ok: boolean(),
          duration_ms: non_neg_integer(),
          before_state: String.t() | nil,
          after_state: String.t() | nil,
          state_changed: boolean(),
          decision: map() | nil,
          transition: map() | nil,
          reconciliation: map() | nil,
          probe_count: non_neg_integer(),
          passed_count: non_neg_integer(),
          failed_count: non_neg_integer(),
          probes: [probe_result()]
        }

  @spec build(
          String.t() | nil,
          String.t() | nil,
          map() | nil,
          ReconciliationConfig.t() | nil,
          String.t(),
          Issue.t() | map() | nil,
          Issue.t() | map() | nil,
          [map()],
          [map()],
          [probe_result()],
          integer(),
          String.t() | nil
        ) :: t()
  def build(
        workflow_label,
        issue_id,
        settings,
        reconciliation_config,
        mode,
        before_issue,
        after_issue,
        issue_events,
        recent_events,
        probes,
        duration_ms,
        shadow_run_id \\ nil
      )
      when is_list(issue_events) and is_list(recent_events) and is_list(probes) do
    passed_count = Enum.count(probes, & &1.ok)
    failed_count = length(probes) - passed_count
    decision = latest_event(issue_events, Contract.event_name(:decision))
    transition = latest_transition_event(issue_events)
    reconciliation = latest_event(recent_events, Contract.event_name(:reconciliation_completed))

    %{
      workflow: workflow_label,
      issue_id: issue_id,
      tracker_kind: tracker_kind(settings),
      repo_provider_kind: repo_provider_kind(settings),
      project_id: project_ref_value(settings, :id),
      project_url: project_ref_value(settings, :url),
      candidate_discovery: candidate_discovery(reconciliation_config),
      mode: mode,
      shadow: shadow_metadata(mode, shadow_run_id),
      ok: failed_count == 0 and not transition_failed?(transition),
      duration_ms: max(duration_ms, 0),
      before_state: issue_state(before_issue),
      after_state: issue_state(after_issue),
      state_changed: issue_state(before_issue) != issue_state(after_issue),
      decision: summarize_event(decision),
      transition: summarize_event(transition),
      reconciliation: summarize_event(reconciliation),
      probe_count: length(probes),
      passed_count: passed_count,
      failed_count: failed_count,
      probes: Enum.map(probes, &scrub_map/1)
    }
  end

  @spec format_text(t()) :: String.t()
  def format_text(report) when is_map(report) do
    report
    |> text_lines()
    |> Enum.map(&scrub_text/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @spec to_map(t()) :: map()
  def to_map(report) when is_map(report), do: scrub_map(report)

  defp text_lines(report) do
    lines =
      [text_header(report)] ++
        decision_text_line(report.decision) ++
        transition_text_line(report.transition) ++
        probe_text_lines(report.probes)

    shadow_prefixed_lines(report, lines)
  end

  defp text_header(report) do
    status = ResultStatus.report_status(report.ok)

    "change proposal one-shot #{status} issue=#{report.issue_id || ResultStatus.unknown()} mode=#{report.mode} " <>
      "tracker=#{report.tracker_kind || ResultStatus.unknown()} repo_provider=#{report.repo_provider_kind || ResultStatus.unknown()} " <>
      "before=#{report.before_state || ResultStatus.unknown()} after=#{report.after_state || ResultStatus.unknown()}"
  end

  defp decision_text_line(nil), do: []

  defp decision_text_line(decision) when is_map(decision) do
    [
      "decision=#{Map.get(decision, Fields.decision()) || ResultStatus.unknown()} reason=#{Map.get(decision, Fields.reason()) || ResultStatus.unknown()} " <>
        "target_route=#{Map.get(decision, Fields.target_route()) || ResultStatus.none()}"
    ]
  end

  defp transition_text_line(nil), do: []

  defp transition_text_line(transition) when is_map(transition) do
    [
      "transition=#{Map.get(transition, Fields.event()) || ResultStatus.unknown()} " <>
        "skip_reason=#{Map.get(transition, Fields.skip_reason()) || ResultStatus.none()} target_state=#{Map.get(transition, Fields.target_state()) || ResultStatus.unknown()}"
    ]
  end

  defp probe_text_lines(probes) when is_list(probes) do
    Enum.map(probes, fn probe ->
      status = ResultStatus.line_status(probe.ok)
      detail = if probe.error, do: "#{probe.summary}: #{probe.error}", else: probe.summary
      "- [#{status}] #{probe.id} #{detail} (#{probe.duration_ms}ms)"
    end)
  end

  defp shadow_prefixed_lines(report, lines) when is_map(report) and is_list(lines) do
    case Map.get(report, :shadow) do
      %{} = shadow ->
        prefix = Map.get(shadow, "prefix")
        run_id = Map.get(shadow, "run_id")
        authority = Map.get(shadow, "authority")

        Enum.map(lines, fn line ->
          "#{prefix} shadow_run_id=#{run_id} shadow_authority=#{authority} #{line}"
        end)

      _shadow ->
        lines
    end
  end

  defp latest_transition_event(events) when is_list(events) do
    Enum.find(events, fn event -> Map.get(event, Fields.event()) in Contract.transition_events() end)
  end

  defp latest_event(events, event_name) when is_list(events) and is_binary(event_name) do
    Enum.find(events, fn event -> Map.get(event, Fields.event()) == event_name end)
  end

  defp summarize_event(nil), do: nil

  defp summarize_event(event) when is_map(event) do
    Map.take(event, Fields.summary_fields())
    |> scrub_map()
  end

  defp scrub_map(map) when is_map(map) do
    case Scrubber.scrub_map(map) do
      {:ok, scrubbed} -> scrubbed
      {:error, reason} -> %{redaction_error: reason}
    end
  end

  defp scrub_text(text) when is_binary(text) do
    case Scrubber.scrub(text) do
      {:ok, scrubbed} when is_binary(scrubbed) -> scrubbed
      _result -> "[REDACTED]"
    end
  end

  defp shadow_metadata(mode, run_id) when is_binary(run_id) do
    if OneShotContract.shadow_mode?(mode) do
      %{
        "prefix" => OneShotContract.shadow_prefix(),
        "run_id" => run_id,
        "mode" => OneShotContract.shadow_mode(),
        "authority" => OneShotContract.shadow_authority(),
        "canonical_authority" => false,
        "allowed_destinations" => OneShotContract.shadow_allowed_destinations()
      }
    end
  end

  defp shadow_metadata(_mode, _run_id), do: nil

  defp transition_failed?(%{} = transition), do: Map.get(transition, Fields.event()) == Contract.event_name(:transition_failed)
  defp transition_failed?(_transition), do: false

  defp tracker_kind(settings) when is_map(settings) do
    settings
    |> settings_tracker()
    |> tracker_kind_value()
    |> normalize_optional_string()
  end

  defp tracker_kind(_settings), do: nil

  defp repo_provider_kind(settings) when is_map(settings) do
    settings
    |> settings_repo()
    |> repo_provider()
    |> repo_provider_kind_value()
    |> normalize_optional_string()
  end

  defp repo_provider_kind(_settings), do: nil

  defp project_ref_value(settings, key) when is_map(settings) and key in [:id, :url] do
    settings
    |> settings_tracker()
    |> project_ref()
    |> case do
      %ProjectRef{} = ref -> ref |> Map.get(key) |> normalize_optional_string()
      _ref -> nil
    end
  end

  defp project_ref_value(_settings, _key), do: nil

  defp project_ref(tracker) when is_map(tracker), do: Tracker.project_ref(tracker)
  defp project_ref(_tracker), do: nil

  defp candidate_discovery(%ReconciliationConfig{candidate_discovery: discovery}), do: Atom.to_string(discovery)
  defp candidate_discovery(_config), do: nil

  defp issue_state(%Issue{state: state}), do: normalize_optional_string(state)
  defp issue_state(issue) when is_map(issue), do: issue |> map_value(:state) |> normalize_optional_string()
  defp issue_state(_issue), do: nil

  defp settings_tracker(%{tracker: tracker}), do: tracker
  defp settings_tracker(%{"tracker" => tracker}), do: tracker
  defp settings_tracker(_settings), do: nil

  defp tracker_kind_value(%{kind: kind}), do: kind
  defp tracker_kind_value(%{"kind" => kind}), do: kind
  defp tracker_kind_value(_tracker), do: nil

  defp settings_repo(%{repo: repo}), do: repo
  defp settings_repo(%{"repo" => repo}), do: repo
  defp settings_repo(_settings), do: nil

  defp repo_provider(%{provider: provider}), do: provider
  defp repo_provider(%{"provider" => provider}), do: provider
  defp repo_provider(_repo), do: nil

  defp repo_provider_kind_value(%{kind: kind}), do: kind
  defp repo_provider_kind_value(%{"kind" => kind}), do: kind
  defp repo_provider_kind_value(_provider), do: nil

  defp map_value(map, key) when is_map(map) and is_atom(key), do: Map.get(map, Atom.to_string(key))

  defp map_value(_map, _key), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  defp normalize_optional_string(value) when is_integer(value), do: value |> Integer.to_string() |> normalize_optional_string()
  defp normalize_optional_string(_value), do: nil
end
