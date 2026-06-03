defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent do
  @moduledoc """
  Normalizes provider-native plan/todo/task surfaces into non-authoritative
  session events.

  These records are correlation and display metadata only. They are not
  evidence refs and cannot satisfy canonical structured plan item requirements.
  """

  alias SymphonyElixir.Observability.Redaction

  @schema_id "workflow.execution_plan.provider_session_event.v1"
  @extension_key "symphony.provider_session_events"
  @authority "non_authoritative"
  @default_trust_class "agent_declared"
  @max_tasks 50
  @max_text_bytes 240
  @max_summary_bytes 512

  @surfaces ~w(agent_visible_plan provider_session_tasks hook_observation canonical_execution_plan_proposal)
  @allowed_event_keys ~w(schema authority trust_class provider_kind surface event_id run_id observed_at tasks hook_observation warnings extensions)
  @required_event_keys ~w(schema authority trust_class provider_kind surface event_id observed_at)
  @allowed_task_keys ~w(provider_task_id title requested_status note correlation)
  @allowed_hook_keys ~w(hook_name phase status summary)

  @surface_alias_by_name %{
    "plan" => "agent_visible_plan",
    "agent_plan" => "agent_visible_plan",
    "todos" => "provider_session_tasks",
    "todo" => "provider_session_tasks",
    "tasks" => "provider_session_tasks",
    "hook" => "hook_observation",
    "hooks" => "hook_observation"
  }
  @trust_class_by_name %{
    "agent_requested" => "agent_requested"
  }
  @task_status_by_name [
                         {~w(complete completed done success succeeded passed pass), "complete"},
                         {~w(pending todo open queued planned), "pending"},
                         {~w(in_progress running started active doing), "in_progress"},
                         {["blocked"], "blocked"},
                         {~w(failed failure error), "failed"},
                         {~w(skipped skip cancelled canceled), "skipped"}
                       ]
                       |> Enum.flat_map(fn {aliases, status} -> Enum.map(aliases, &{&1, status}) end)
                       |> Map.new()

  @type normalized_event :: map()

  @spec schema_id() :: String.t()
  def schema_id, do: @schema_id

  @spec extension_key() :: String.t()
  def extension_key, do: @extension_key

  @spec normalize(map(), keyword()) :: {:ok, normalized_event()} | {:error, map()}
  def normalize(event, opts \\ [])

  def normalize(event, opts) when is_map(event) and is_list(opts) do
    normalized =
      %{
        "schema" => @schema_id,
        "authority" => @authority,
        "trust_class" => trust_class(event),
        "provider_kind" => provider_kind(event, opts),
        "surface" => surface(event),
        "event_id" => event_id(event),
        "run_id" => string_value(event, "run_id") || keyword_string(opts, :run_id),
        "observed_at" => string_value(event, "observed_at") || keyword_string(opts, :observed_at),
        "tasks" => tasks(event),
        "hook_observation" => hook_observation(event),
        "warnings" => warnings(event)
      }
      |> compact()

    validate(normalized)
  end

  def normalize(_event, _opts) do
    {:error, %{code: "provider_session_event_invalid", message: "Provider session event must be an object."}}
  end

  @spec validate(map()) :: {:ok, normalized_event()} | {:error, map()}
  def validate(event) when is_map(event) do
    errors =
      []
      |> collect_required_keys(event)
      |> collect_unknown_event_keys(event)
      |> collect_literal(event, "schema", @schema_id)
      |> collect_literal(event, "authority", @authority)
      |> collect_string(event, "provider_kind")
      |> collect_surface(event)
      |> collect_string(event, "event_id")
      |> collect_optional_string(event, "run_id")
      |> collect_string(event, "observed_at")
      |> collect_tasks(event)
      |> collect_hook_observation(event)

    if errors == [] do
      {:ok, event}
    else
      {:error, %{code: "provider_session_event_invalid", message: "Provider session event is invalid.", errors: errors}}
    end
  end

  def validate(_event) do
    {:error, %{code: "provider_session_event_invalid", message: "Provider session event must be an object."}}
  end

  defp provider_kind(event, opts) do
    string_value(event, "provider_kind") || string_value(event, "provider") || keyword_string(opts, :provider_kind)
  end

  defp surface(event) do
    raw =
      string_value(event, "surface") ||
        cond do
          Map.has_key?(event, "hook") or Map.has_key?(event, :hook) -> "hook_observation"
          task_values(event) != [] -> "provider_session_tasks"
          true -> nil
        end

    case raw && raw |> String.downcase() |> String.replace(~r/[^a-z0-9]+/u, "_") |> String.trim("_") do
      value when value in @surfaces -> value
      value when is_binary(value) -> Map.get(@surface_alias_by_name, value, value)
      value -> value
    end
  end

  defp event_id(event) do
    string_value(event, "event_id") ||
      string_value(event, "id") ||
      "provider-session-" <> (event |> Redaction.redact() |> :erlang.term_to_binary() |> sha256())
  end

  defp trust_class(event) do
    @trust_class_by_name
    |> Map.get(string_value(event, "trust_class"), @default_trust_class)
  end

  defp tasks(event) do
    event
    |> task_values()
    |> Enum.take(@max_tasks)
    |> Enum.with_index()
    |> Enum.flat_map(fn {task, index} -> normalize_task(task, index) end)
  end

  defp task_values(event) do
    ["tasks", "todos", "plan", "entries", "items"]
    |> Enum.find_value([], fn key ->
      case fetch_existing(event, key) do
        values when is_list(values) -> values
        _value -> nil
      end
    end)
  end

  defp normalize_task(task, index) when is_map(task) do
    task_id =
      string_value(task, "provider_task_id") ||
        string_value(task, "task_id") ||
        string_value(task, "id") ||
        string_value(task, "uuid") ||
        "provider-task-#{index + 1}"

    [
      %{
        "provider_task_id" => bounded_string(task_id),
        "title" => task_title(task),
        "requested_status" => task_status(task),
        "note" => task_note(task),
        "correlation" => %{
          "provider_position" => index,
          "provider_surface" => "provider_session_tasks"
        }
      }
      |> compact()
    ]
  end

  defp normalize_task(task, index) when is_binary(task) do
    [
      %{
        "provider_task_id" => "provider-task-#{index + 1}",
        "title" => bounded_string(task),
        "requested_status" => "unknown",
        "correlation" => %{"provider_position" => index, "provider_surface" => "provider_session_tasks"}
      }
    ]
  end

  defp normalize_task(_task, _index), do: []

  defp task_title(task) do
    ["title", "content", "text", "description", "name", "summary"]
    |> Enum.find_value(&string_value(task, &1))
    |> bounded_string()
  end

  defp task_note(task) do
    ["note", "notes", "details"]
    |> Enum.find_value(&string_value(task, &1))
    |> bounded_string()
  end

  defp task_status(task) do
    ["status", "state", "phase"]
    |> Enum.find_value(&string_value(task, &1))
    |> normalize_status()
  end

  defp hook_observation(event) do
    hook_source = fetch_existing(event, "hook")

    if surface(event) == "hook_observation" or is_map(hook_source) do
      hook = if is_map(hook_source), do: hook_source, else: event
      payload = fetch_existing(event, "payload") || event

      %{
        "hook_name" => hook |> string_value("hook_name") |> Kernel.||(string_value(hook, "name")) |> bounded_string(),
        "phase" => hook |> string_value("phase") |> bounded_string(),
        "status" => hook |> string_value("status") |> normalize_status(),
        "summary" => Redaction.summarize(payload, @max_summary_bytes)
      }
      |> compact()
    end
  end

  defp warnings(event) do
    base = ["provider_native_status_non_authoritative"]

    if completed_task?(event) do
      ["provider_native_complete_does_not_satisfy_evidence" | base]
    else
      base
    end
    |> Enum.uniq()
  end

  defp completed_task?(event) do
    event
    |> task_values()
    |> Enum.any?(fn
      task when is_map(task) -> task_status(task) == "complete"
      _task -> false
    end)
  end

  defp normalize_status(nil), do: "unknown"

  defp normalize_status(status) when is_binary(status) do
    normalized = status |> String.downcase() |> String.replace(~r/[^a-z0-9]+/u, "_") |> String.trim("_")
    Map.get(@task_status_by_name, normalized, "unknown")
  end

  defp normalize_status(_status), do: "unknown"

  defp collect_required_keys(errors, event) do
    missing =
      @required_event_keys
      |> Enum.reject(fn key -> present?(Map.get(event, key)) end)
      |> Enum.map(&%{code: "missing_required_field", path: [&1], message: "Required provider session event field is missing."})

    errors ++ missing
  end

  defp collect_unknown_event_keys(errors, event) do
    unknown =
      event
      |> Map.keys()
      |> Enum.reject(&(&1 in @allowed_event_keys))
      |> Enum.map(&%{code: "unknown_field", path: [&1], message: "Provider session event field is not supported."})

    errors ++ unknown
  end

  defp collect_literal(errors, event, key, expected) do
    if Map.get(event, key) == expected, do: errors, else: errors ++ [%{code: "invalid_value", path: [key], message: "Provider session event field has an unsupported value."}]
  end

  defp collect_string(errors, event, key) do
    if is_binary(Map.get(event, key)) and String.trim(Map.get(event, key)) != "" do
      errors
    else
      errors ++ [%{code: "invalid_type", path: [key], message: "Provider session event field must be a non-empty string."}]
    end
  end

  defp collect_optional_string(errors, event, key) do
    case Map.get(event, key) do
      nil -> errors
      value when is_binary(value) -> errors
      _value -> errors ++ [%{code: "invalid_type", path: [key], message: "Provider session event field must be a string."}]
    end
  end

  defp collect_surface(errors, event) do
    if Map.get(event, "surface") in @surfaces do
      errors
    else
      errors ++ [%{code: "invalid_enum", path: ["surface"], message: "Provider session event surface is unsupported."}]
    end
  end

  defp collect_tasks(errors, %{"tasks" => tasks}) when is_list(tasks) do
    task_errors =
      tasks
      |> Enum.with_index()
      |> Enum.flat_map(fn {task, index} -> task_errors(task, index) end)

    errors ++ task_errors
  end

  defp collect_tasks(errors, %{"tasks" => _tasks}) do
    errors ++ [%{code: "invalid_type", path: ["tasks"], message: "Provider session event tasks must be an array."}]
  end

  defp collect_tasks(errors, _event), do: errors

  defp task_errors(task, index) when is_map(task) do
    path = ["tasks", index]

    task
    |> Map.keys()
    |> Enum.reject(&(&1 in @allowed_task_keys))
    |> Enum.map(&%{code: "unknown_field", path: path ++ [&1], message: "Provider session task field is not supported."})
  end

  defp task_errors(_task, index), do: [%{code: "invalid_type", path: ["tasks", index], message: "Provider session task must be an object."}]

  defp collect_hook_observation(errors, %{"hook_observation" => hook}) when is_map(hook) do
    unknown =
      hook
      |> Map.keys()
      |> Enum.reject(&(&1 in @allowed_hook_keys))
      |> Enum.map(&%{code: "unknown_field", path: ["hook_observation", &1], message: "Provider hook observation field is not supported."})

    errors ++ unknown
  end

  defp collect_hook_observation(errors, %{"hook_observation" => _hook}) do
    errors ++ [%{code: "invalid_type", path: ["hook_observation"], message: "Provider hook observation must be an object."}]
  end

  defp collect_hook_observation(errors, _event), do: errors

  defp fetch_existing(map, key) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        map_get_existing_atom(map, key)
    end
  end

  defp fetch_existing(_map, _key), do: nil

  defp string_value(map, key) when is_map(map) do
    case fetch_existing(map, key) do
      value when is_binary(value) -> value
      value when is_integer(value) -> Integer.to_string(value)
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      _value -> nil
    end
  end

  defp string_value(_map, _key), do: nil

  defp keyword_string(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) -> value
      value when is_integer(value) -> Integer.to_string(value)
      _value -> nil
    end
  end

  defp map_get_existing_atom(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp bounded_string(nil), do: nil

  defp bounded_string(value) when is_binary(value) do
    value
    |> Redaction.redact_string()
    |> String.trim()
    |> truncate(@max_text_bytes)
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp truncate(value, max_bytes) when byte_size(value) <= max_bytes, do: value

  defp truncate(value, max_bytes) do
    value
    |> binary_part(0, max_bytes)
    |> valid_prefix()
    |> Kernel.<>("...<truncated>")
  end

  defp valid_prefix(value) do
    if String.valid?(value), do: value, else: value |> binary_part(0, byte_size(value) - 1) |> valid_prefix()
  end

  defp sha256(value) do
    :crypto.hash(:sha256, value)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 24)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)

  defp compact(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) or value == [] or value == %{} end)
  end
end
