defmodule SymphonyElixir.Workflow.CompletionValidator do
  @moduledoc """
  Validates machine-readable completion evidence for workflow profiles.

  The first implementation targets `coding_pr_delivery`. It is intentionally
  pure and evidence-driven: callers supply observed tracker/repo facts, and the
  validator reports which contract checks are satisfied.
  """

  alias SymphonyElixir.Workflow.IssueContext
  alias SymphonyElixir.Workflow.ProfileRegistry

  @coding_profile "coding_pr_delivery"
  @merge_capabilities MapSet.new(["repo_provider.merge", "repo.merge_change_proposal"])

  @type validation_status :: String.t()
  @type validation_result :: %{
          required(String.t()) => term()
        }

  @spec validate(map(), keyword() | map()) :: validation_result()
  def validate(issue, opts \\ [])

  def validate(issue, opts) when is_map(issue) do
    profile_context = profile_context(issue, opts)
    evidence = evidence(issue, opts)
    contract = completion_contract(issue, profile_context)
    allowed_routes = string_list(map_field(contract, :allowed_completion_routes))
    route_key = completion_route(issue, opts, evidence)

    if profile_context.kind == @coding_profile do
      checks = [
        check("change_proposal_exists", change_proposal_exists?(evidence), "linked change proposal exists", observed_change_proposal(evidence)),
        check(
          "change_proposal_linked_to_tracker",
          change_proposal_linked_to_tracker?(evidence),
          "change proposal is attached or linked to the tracker issue",
          observed_tracker_link(evidence)
        ),
        check("commit_or_diff_exists", commit_or_diff_exists?(evidence), "commit or diff evidence exists", observed_repo_change(evidence)),
        check(
          "checks_read_and_recorded",
          checks_read_and_recorded?(evidence),
          "CI/check evidence was read and recorded",
          observed_checks(evidence)
        ),
        check(
          "tracker_workpad_written",
          tracker_workpad_written?(evidence),
          "tracker workpad/comment was written",
          observed_tracker_write(evidence)
        ),
        check(
          "completion_route_allowed",
          route_allowed?(route_key, allowed_routes),
          "current or target route is allowed by the completion contract",
          observed_route(route_key)
        )
      ]

      %{
        "status" => result_status(checks),
        "profile" => profile_context.kind,
        "route" => route_key,
        "allowed_completion_routes" => allowed_routes,
        "checks" => checks,
        "missing_evidence" => missing_evidence(checks),
        "observed_evidence" => observed_evidence(checks)
      }
    else
      %{
        "status" => "skipped",
        "profile" => profile_context.kind,
        "route" => route_key,
        "allowed_completion_routes" => allowed_routes,
        "checks" => [],
        "missing_evidence" => [],
        "observed_evidence" => []
      }
    end
  end

  def validate(_issue, _opts), do: validate(%{}, [])

  @spec merge_gate(map(), map()) :: validation_result()
  def merge_gate(evidence, capabilities \\ %{})

  def merge_gate(evidence, capabilities) when is_map(evidence) and is_map(capabilities) do
    checks = [
      check("change_proposal_exists", change_proposal_exists?(evidence), "linked change proposal exists", observed_change_proposal(evidence)),
      check(
        "change_proposal_approved",
        change_proposal_approved?(evidence),
        "required human approval is present",
        observed_approval(evidence)
      ),
      check("checks_passing", checks_passing?(evidence), "required CI/checks passed", observed_checks(evidence)),
      check(
        "merge_capability_available",
        merge_capability_available?(capabilities),
        "merge capability is available",
        observed_merge_capability(capabilities)
      ),
      check(
        "tracker_merge_state_observed",
        tracker_merge_state_observed?(evidence),
        "tracker state or approval evidence indicates merge is authorized",
        observed_tracker_merge_state(evidence)
      )
    ]

    %{
      "status" => result_status(checks),
      "checks" => checks,
      "missing_evidence" => missing_evidence(checks),
      "observed_evidence" => observed_evidence(checks)
    }
  end

  def merge_gate(_evidence, capabilities) when is_map(capabilities), do: merge_gate(%{}, capabilities)
  def merge_gate(evidence, _capabilities) when is_map(evidence), do: merge_gate(evidence, %{})
  def merge_gate(_evidence, _capabilities), do: merge_gate(%{}, %{})

  defp check(key, true, required_evidence, observed_evidence) do
    %{
      "key" => key,
      "status" => "passed",
      "required_evidence" => required_evidence,
      "observed_evidence" => observed_evidence
    }
  end

  defp check(key, _passed?, required_evidence, observed_evidence) do
    %{
      "key" => key,
      "status" => "failed",
      "required_evidence" => required_evidence,
      "observed_evidence" => observed_evidence
    }
  end

  defp result_status(checks) do
    if Enum.all?(checks, &(Map.get(&1, "status") == "passed")) do
      "passed"
    else
      "failed"
    end
  end

  defp missing_evidence(checks) do
    checks
    |> Enum.reject(&(Map.get(&1, "status") == "passed"))
    |> Enum.map(&Map.fetch!(&1, "required_evidence"))
  end

  defp observed_evidence(checks) do
    checks
    |> Enum.flat_map(&List.wrap(Map.get(&1, "observed_evidence")))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp profile_context(issue, opts) do
    issue_profile = issue |> workflow_value(:profile) |> normalize_map()
    settings_profile = opts |> opt(:settings) |> map_field(:workflow) |> map_field(:profile) |> normalize_map()

    profile_config =
      cond do
        map_size(issue_profile) > 0 -> issue_profile
        map_size(settings_profile) > 0 -> settings_profile
        true -> ProfileRegistry.default_profile_config()
      end

    case ProfileRegistry.resolve(profile_config) do
      {:ok, resolved_profile} -> resolved_profile
      {:error, _reason} -> ProfileRegistry.resolve!(nil)
    end
  end

  defp completion_contract(issue, profile_context) do
    case workflow_value(issue, :completion_contract) do
      contract when is_map(contract) -> contract
      _contract -> ProfileRegistry.completion_contract(profile_context.module, profile_context.options)
    end
  end

  defp completion_route(issue, opts, evidence) do
    opt(opts, :target_route) ||
      evidence |> map_field(:route) |> route_value(:target) ||
      evidence |> map_field(:route) |> route_value(:current) ||
      evidence |> route_value(:target_route) ||
      evidence |> route_value(:route_key) ||
      issue_route_key(issue)
  end

  defp issue_route_key(issue) do
    case IssueContext.route_facts(issue) do
      %{route_key: route_key} when is_atom(route_key) -> Atom.to_string(route_key)
      _route_facts -> nil
    end
  end

  defp route_allowed?(route_key, allowed_routes) when is_binary(route_key) and is_list(allowed_routes),
    do: route_key in allowed_routes

  defp route_allowed?(_route_key, _allowed_routes), do: false

  defp change_proposal_exists?(evidence) do
    change_proposal =
      first_map([
        map_field(evidence, :change_proposal),
        map_field(evidence, :changeProposal),
        evidence |> map_field(:data) |> map_field(:changeProposal),
        evidence |> map_field(:data) |> map_field(:change_proposal),
        map_field(evidence, :pr),
        map_field(evidence, :pull_request)
      ])

    truthy?(map_field(change_proposal, :exists)) or
      present_string?(map_field(change_proposal, :url)) or
      present_string?(map_field(change_proposal, :number)) or
      present_string?(map_field(change_proposal, :target))
  end

  defp change_proposal_linked_to_tracker?(evidence) do
    attachment =
      first_map([
        map_field(evidence, :attachment),
        evidence |> map_field(:data) |> map_field(:attachment),
        evidence |> map_field(:tracker) |> map_field(:attachment)
      ])

    truthy?(deep_field(evidence, [:tracker, :change_proposal_attached])) or
      truthy?(deep_field(evidence, [:tracker, :tracker_attached])) or
      truthy?(deep_field(evidence, [:change_proposal, :linked_issue])) or
      truthy?(deep_field(evidence, [:changeProposal, :linkedIssue])) or
      truthy?(deep_field(evidence, [:change_proposal, :tracker_linked])) or
      present_string?(map_field(attachment, :url)) or
      present_string?(map_field(attachment, :id))
  end

  defp commit_or_diff_exists?(evidence) do
    repo = map_field(evidence, :repo)
    commits = map_field(repo, :commits) || map_field(evidence, :commits)
    diff = map_field(repo, :diff) || map_field(evidence, :diff)

    truthy?(map_field(repo, :commit_exists)) or
      truthy?(map_field(repo, :diff_exists)) or
      truthy?(map_field(repo, :diff_present)) or
      non_empty_list?(commits) or
      present_string?(map_field(repo, :head_sha)) or
      present_string?(map_field(diff, :summary)) or
      truthy?(map_field(diff, :present))
  end

  defp checks_read_and_recorded?(evidence) do
    checks = checks_map(evidence)

    (truthy?(map_field(checks, :read)) and checks_result_recorded?(checks)) or
      non_empty_list?(map_field(checks, :items)) or
      non_empty_list?(map_field(checks, :checks))
  end

  defp checks_passing?(evidence) do
    checks = checks_map(evidence)

    map_field(checks, :status) in ["passing", "passed", "success", "successful"] or
      map_field(checks, :summary) in ["passing", "passed", "success", "successful"] or
      map_field(checks, :check_summary) == "passing" or
      truthy?(map_field(checks, :passing))
  end

  defp checks_result_recorded?(checks) when is_map(checks) do
    present_string?(map_field(checks, :status)) or
      present_string?(map_field(checks, :summary)) or
      present_string?(map_field(checks, :check_summary)) or
      truthy?(map_field(checks, :recorded))
  end

  defp checks_map(evidence) do
    first_map([
      map_field(evidence, :checks),
      evidence |> map_field(:data) |> map_field(:checks),
      map_field(evidence, :ci),
      evidence |> map_field(:change_proposal) |> map_field(:checks),
      evidence |> map_field(:changeProposal) |> map_field(:checks)
    ])
  end

  defp tracker_workpad_written?(evidence) do
    tracker = map_field(evidence, :tracker)

    truthy?(map_field(tracker, :workpad_written)) or
      truthy?(map_field(tracker, :comment_written)) or
      truthy?(map_field(tracker, :workpad_upserted)) or
      present_string?(deep_field(evidence, [:data, :comment, :id])) or
      present_string?(deep_field(evidence, [:tracker, :comment, :id]))
  end

  defp change_proposal_approved?(evidence) do
    review =
      first_map([
        map_field(evidence, :review),
        map_field(evidence, :reviews),
        evidence |> map_field(:change_proposal) |> map_field(:review),
        evidence |> map_field(:changeProposal) |> map_field(:review)
      ])

    map_field(review, :status) in ["approved", "approval", "passed"] or
      map_field(review, :summary) == "approved" or
      map_field(review, :review_summary) == "approved" or
      truthy?(map_field(review, :approved))
  end

  defp merge_capability_available?(%{"checked" => false}), do: false
  defp merge_capability_available?(%{checked: false}), do: false

  defp merge_capability_available?(capabilities) when is_map(capabilities) do
    available =
      capabilities
      |> map_field(:available)
      |> capability_set()

    missing =
      capabilities
      |> map_field(:missing)
      |> capability_set()

    Enum.any?(@merge_capabilities, &MapSet.member?(available, &1)) and
      Enum.all?(@merge_capabilities, &(not MapSet.member?(missing, &1)))
  end

  defp tracker_merge_state_observed?(evidence) do
    route = map_field(evidence, :route)
    tracker = map_field(evidence, :tracker)

    route_value(route, :key) == "merging" or
      route_value(route, :current) == "merging" or
      route_value(route, :target) == "merging" or
      map_field(tracker, :state) in ["Merging", "merging"] or
      truthy?(map_field(tracker, :merge_approved))
  end

  defp observed_change_proposal(evidence) do
    cond do
      present_string?(deep_field(evidence, [:change_proposal, :url])) -> ["change_proposal.url"]
      present_string?(deep_field(evidence, [:changeProposal, :url])) -> ["changeProposal.url"]
      present_string?(deep_field(evidence, [:data, :changeProposal, :url])) -> ["data.changeProposal.url"]
      change_proposal_exists?(evidence) -> ["change_proposal"]
      true -> []
    end
  end

  defp observed_tracker_link(evidence) do
    cond do
      present_string?(deep_field(evidence, [:data, :attachment, :id])) -> ["data.attachment.id"]
      present_string?(deep_field(evidence, [:attachment, :id])) -> ["attachment.id"]
      change_proposal_linked_to_tracker?(evidence) -> ["tracker.change_proposal_attached"]
      true -> []
    end
  end

  defp observed_repo_change(evidence) do
    cond do
      non_empty_list?(deep_field(evidence, [:repo, :commits])) -> ["repo.commits"]
      truthy?(deep_field(evidence, [:repo, :diff_present])) -> ["repo.diff_present"]
      present_string?(deep_field(evidence, [:repo, :head_sha])) -> ["repo.head_sha"]
      true -> []
    end
  end

  defp observed_checks(evidence) do
    cond do
      checks_passing?(evidence) -> ["checks.passing"]
      checks_read_and_recorded?(evidence) -> ["checks.read"]
      true -> []
    end
  end

  defp observed_tracker_write(evidence) do
    if tracker_workpad_written?(evidence), do: ["tracker.workpad_written"], else: []
  end

  defp observed_route(route_key) when is_binary(route_key), do: ["route=#{route_key}"]
  defp observed_route(_route_key), do: []

  defp observed_approval(evidence) do
    if change_proposal_approved?(evidence), do: ["review.approved"], else: []
  end

  defp observed_merge_capability(capabilities) do
    if merge_capability_available?(capabilities), do: ["merge_capability.available"], else: []
  end

  defp observed_tracker_merge_state(evidence) do
    if tracker_merge_state_observed?(evidence), do: ["tracker.merge_state"], else: []
  end

  defp evidence(issue, opts) when is_map(issue) do
    opts_evidence = opt(opts, :evidence)

    cond do
      is_map(opts_evidence) ->
        opts_evidence

      is_map(workflow_value(issue, :completion_evidence)) ->
        workflow_value(issue, :completion_evidence)

      is_map(workflow_value(issue, :evidence)) ->
        workflow_value(issue, :evidence)

      true ->
        %{}
    end
  end

  defp first_map(values) when is_list(values) do
    Enum.find_value(values, %{}, fn
      value when is_map(value) -> value
      _value -> nil
    end)
  end

  defp non_empty_list?(values) when is_list(values), do: values != []
  defp non_empty_list?(_values), do: false

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("yes"), do: true
  defp truthy?("passed"), do: true
  defp truthy?("passing"), do: true
  defp truthy?(1), do: true
  defp truthy?(_value), do: false

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(value) when is_integer(value), do: true
  defp present_string?(_value), do: false

  defp capability_set(%MapSet{} = values), do: values

  defp capability_set(values) do
    values
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

  defp string_list(values) do
    values
    |> List.wrap()
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp route_value(map, key) when is_map(map) do
    map
    |> map_field(key)
    |> normalize_string()
  end

  defp route_value(_map, _key), do: nil

  defp deep_field(value, []), do: value

  defp deep_field(value, [key | rest]) do
    value
    |> map_field(key)
    |> deep_field(rest)
  end

  defp workflow_value(issue, key) when is_map(issue) and is_atom(key) do
    issue
    |> map_field(:workflow)
    |> map_field(key)
  end

  defp opt(opts, key, default \\ nil)
  defp opt(opts, key, default) when is_list(opts) and is_atom(key), do: Keyword.get(opts, key, default)
  defp opt(opts, key, default) when is_map(opts) and is_atom(key), do: map_field(opts, key) || default
  defp opt(_opts, _key, default), do: default

  defp map_field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_field(_map, _key), do: nil

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(value) when is_atom(value) and not is_boolean(value), do: Atom.to_string(value)
  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(_value), do: nil
end
