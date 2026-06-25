defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.PreflightReportCollector do
  @moduledoc """
  Collects Phase 2 read-only provider preflight results into bounded metadata.

  The collector may call read-only tracker/repo-provider smoke probes. It never
  passes write/destructive flags, stores raw stdout/stderr, reads evidence files,
  mutates workflow state, approves production, or enables gates.
  """

  alias SymphonyElixir.CLI.{RepoProviderSmoke, TrackerSmoke}
  alias SymphonyElixir.RepoProvider.CLI.Evaluator, as: RepoProviderEvaluator
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.PreflightReport

  @report_schema "coding_pr_delivery.provider_preflight_report.v1"
  @error_code "coding_pr_delivery_preflight_report_collector_invalid"
  @non_claims [
    "preflight_report_does_not_enable_production",
    "preflight_report_does_not_mutate_workflow_state",
    "preflight_report_uses_read_only_provider_smokes"
  ]

  @type validation_result :: {:ok, map()} | {:error, map()}

  @type deps :: %{
          required(:env) => (-> map() | [{String.t(), String.t()}]),
          required(:utc_now) => (-> DateTime.t()),
          required(:tracker_smoke) => ([String.t()] -> {String.t(), String.t(), non_neg_integer()}),
          required(:repo_provider_smoke) => ([String.t()] -> {String.t(), String.t(), non_neg_integer()})
        }

  @spec collect(map(), keyword(), deps()) :: validation_result()
  def collect(phase2_plan, opts \\ [], deps \\ runtime_deps())

  def collect(phase2_plan, opts, deps) when is_map(phase2_plan) and is_list(opts) and is_map(deps) do
    with true <- Keyword.keyword?(opts),
         :ok <- validate_deps(deps) do
      phase2_plan
      |> report_packet(opts, deps)
      |> PreflightReport.validate()
    else
      false ->
        {:error, invalid([issue("invalid_options", [], "Preflight collector options must be a keyword list.")])}

      {:error, reason} ->
        {:error, invalid([reason])}
    end
  end

  def collect(_phase2_plan, _opts, _deps) do
    {:error, invalid([issue("invalid_type", [], "Preflight collector requires a Phase 2 evidence plan object.")])}
  end

  @spec runtime_deps() :: deps()
  def runtime_deps do
    %{
      env: &System.get_env/0,
      utc_now: fn -> DateTime.utc_now() end,
      tracker_smoke: fn argv -> TrackerSmoke.evaluate(argv) end,
      repo_provider_smoke: fn argv ->
        RepoProviderSmoke.evaluate(argv, %{
          env: &System.get_env/0,
          command_opts: fn -> [] end,
          cli_evaluate: fn argv, cli_deps ->
            cli_deps = Map.put(cli_deps, :emit_event, fn _level, _event, payload -> payload end)
            RepoProviderEvaluator.evaluate(argv, cli_deps)
          end,
          monotonic_time_ms: fn -> System.monotonic_time(:millisecond) end,
          emit_event: fn _level, _event, payload -> payload end
        })
      end
    }
  end

  defp report_packet(phase2_plan, opts, deps) do
    env = deps.env.() |> normalize_env()
    ran_at = deps.utc_now.() |> DateTime.to_iso8601()

    %{
      "schema" => @report_schema,
      "phase2_evidence_plan" => phase2_plan,
      "provider_preflight_results" => provider_preflight_results(phase2_plan, opts, deps, env, ran_at),
      "explicit_non_claims" => @non_claims,
      "collector" => %{
        "mode" => "read_only_provider_preflight",
        "raw_output_included" => false,
        "does_not_read_evidence_files" => true,
        "does_not_mutate_workflow_state" => true,
        "does_not_approve_production" => true,
        "does_not_enable_production" => true
      }
    }
  end

  defp provider_preflight_results(phase2_plan, opts, deps, env, ran_at) do
    phase2_plan
    |> Map.get("provider_plans", [])
    |> Enum.flat_map(fn provider_plan ->
      template = Map.get(provider_plan, "template")

      provider_plan
      |> value_at(["read_only_preflight", "commands"])
      |> case do
        commands when is_list(commands) ->
          Enum.map(commands, &preflight_result(template, &1, opts, deps, env, ran_at, phase2_plan))

        _missing ->
          []
      end
    end)
  end

  defp preflight_result(template, command, opts, deps, env, ran_at, phase2_plan) when is_map(command) do
    missing = missing_prerequisites(command, opts, env)

    cond do
      missing != [] ->
        blocked_result(template, command, ran_at, "preflight_prerequisites_missing", missing)

      smoke_passed?(command, opts, deps) ->
        passed_result(template, command, ran_at, phase2_plan, opts)

      true ->
        blocked_result(template, command, ran_at, "preflight_smoke_failed", fallback_prerequisites(command))
    end
  end

  defp preflight_result(template, _command, _opts, _deps, _env, ran_at, _phase2_plan) do
    %{
      "template" => template,
      "command_id" => "invalid-command",
      "target" => "unknown",
      "provider_kind" => "unknown",
      "status" => "blocked",
      "blocker_code" => "invalid_preflight_command",
      "missing_prerequisites" => ["provider_read_only_smoke"],
      "ran_at" => ran_at,
      "side_effect_mode" => "read_only",
      "write_performed" => false,
      "production_enabled" => false
    }
  end

  defp passed_result(template, command, ran_at, phase2_plan, opts) do
    command
    |> base_result(template, ran_at)
    |> Map.put("status", "passed")
    |> Map.put("evidence_files", [evidence_ref(template, command, phase2_plan, opts)])
  end

  defp blocked_result(template, command, ran_at, blocker_code, missing_prerequisites) do
    command
    |> base_result(template, ran_at)
    |> Map.merge(%{
      "status" => "blocked",
      "blocker_code" => blocker_code,
      "missing_prerequisites" => missing_prerequisites
    })
  end

  defp base_result(command, template, ran_at) do
    %{
      "template" => template,
      "command_id" => Map.get(command, "id"),
      "target" => Map.get(command, "target"),
      "provider_kind" => Map.get(command, "provider_kind"),
      "ran_at" => ran_at,
      "side_effect_mode" => "read_only",
      "write_performed" => false,
      "production_enabled" => false
    }
  end

  defp missing_prerequisites(command, opts, env) do
    missing_env =
      command
      |> list_field("required_env")
      |> Enum.reject(&env_present?(env, &1))

    missing_targets =
      command
      |> list_field("required_targets")
      |> Enum.reject(&target_present?(opts, &1))

    Enum.uniq(missing_env ++ missing_targets)
  end

  defp smoke_passed?(%{"target" => "tracker"} = command, _opts, deps) do
    command
    |> tracker_argv()
    |> deps.tracker_smoke.()
    |> smoke_ok?()
  end

  defp smoke_passed?(%{"target" => "repo_provider"} = command, opts, deps) do
    command
    |> repo_provider_argv(opts)
    |> deps.repo_provider_smoke.()
    |> smoke_ok?()
  end

  defp smoke_passed?(_command, _opts, _deps), do: false

  defp tracker_argv(command) do
    ["--template", tracker_template(command), "--json"]
  end

  defp repo_provider_argv(command, opts) do
    [
      "--provider",
      Map.get(command, "provider_kind"),
      "--repo",
      target_value(opts, "repo_slug"),
      "--pr",
      target_value(opts, "change_proposal_number"),
      "--json"
    ]
  end

  defp smoke_ok?({stdout, _stderr, 0}) do
    case Jason.decode(stdout) do
      {:ok, %{"ok" => true}} -> true
      _decoded -> false
    end
  end

  defp smoke_ok?({_stdout, _stderr, _exit_code}), do: false

  defp tracker_template(%{"command" => command}) when is_binary(command) do
    case Regex.run(~r/--template\s+([^\s]+)/, command) do
      [_match, template] -> template
      _missing -> ""
    end
  end

  defp tracker_template(_command), do: ""

  defp fallback_prerequisites(command) do
    command
    |> declared_prerequisites()
    |> case do
      [] -> ["provider_read_only_smoke"]
      prerequisites -> prerequisites
    end
  end

  defp declared_prerequisites(command) do
    ["required_env", "required_auth", "required_targets", "required_runtime"]
    |> Enum.flat_map(&list_field(command, &1))
    |> Enum.uniq()
  end

  defp evidence_ref(template, command, phase2_plan, opts) do
    prefix = opts |> Keyword.get(:evidence_prefix, "evidence/preflight") |> clean_segment()
    plan_id = phase2_plan |> Map.get("plan_id", "phase2") |> clean_segment()
    template = clean_segment(template)
    command_id = command |> Map.get("id", "command") |> clean_segment()

    "#{prefix}/#{plan_id}/#{template}/#{command_id}.json"
  end

  defp clean_segment(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(~r/[^A-Za-z0-9._\/-]/, "-")
    |> String.trim("/")
    |> case do
      "" -> "unknown"
      cleaned -> cleaned
    end
  end

  defp clean_segment(_value), do: "unknown"

  defp env_present?(env, key) do
    case Map.get(env, key) do
      value when is_binary(value) -> String.trim(value) != ""
      _value -> false
    end
  end

  defp target_present?(opts, target), do: is_binary(target_value(opts, target))

  defp target_value(opts, "repo_slug") do
    opts
    |> Keyword.get(:repo_slug, Keyword.get(opts, :repo))
    |> normalize_optional_string()
  end

  defp target_value(opts, "change_proposal_number") do
    opts
    |> Keyword.get(:change_proposal_number, Keyword.get(opts, :pr))
    |> normalize_optional_string()
  end

  defp target_value(_opts, _target), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp list_field(map, field) when is_map(map) do
    case Map.get(map, field) do
      values when is_list(values) -> Enum.filter(values, &non_empty_string?/1)
      _value -> []
    end
  end

  defp non_empty_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp non_empty_string?(_value), do: false

  defp normalize_env(env) when is_map(env), do: env
  defp normalize_env(env) when is_list(env), do: Map.new(env)
  defp normalize_env(_env), do: %{}

  defp validate_deps(%{env: env, utc_now: utc_now, tracker_smoke: tracker_smoke, repo_provider_smoke: repo_provider_smoke})
       when is_function(env, 0) and is_function(utc_now, 0) and is_function(tracker_smoke, 1) and is_function(repo_provider_smoke, 1),
       do: :ok

  defp validate_deps(_deps), do: {:error, issue("invalid_deps", [], "Preflight collector dependencies are invalid.")}

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery preflight report collector is invalid.",
      errors: errors
    }
  end

  defp issue(code, path, message) do
    %{
      code: code,
      path: path,
      message: message
    }
  end

  defp value_at(map, path) when is_map(map) and is_list(path) do
    Enum.reduce_while(path, map, fn key, current ->
      if is_map(current) and Map.has_key?(current, key) do
        {:cont, Map.get(current, key)}
      else
        {:halt, nil}
      end
    end)
  end

  defp value_at(_map, _path), do: nil
end
