defmodule SymphonyElixir.Config.Schema.Tracker do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  @supported_lifecycle_fields MapSet.new([
                                "active_states",
                                "terminal_states",
                                "state_phase_map",
                                "raw_state_by_route_key",
                                "policy_by_route_key",
                                "workflows_by_type",
                                "workflow_profile"
                              ])

  @supported_workflow_by_type_fields MapSet.new([
                                       "active_states",
                                       "terminal_states",
                                       "state_phase_map",
                                       "raw_state_by_route_key",
                                       "policy_by_route_key"
                                     ])

  embedded_schema do
    field(:kind, :string)
    field(:endpoint, :string)
    field(:auth, :map, default: %{})
    field(:provider, :map, default: %{})
    field(:lifecycle, :map, default: %{})
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(
      attrs,
      [
        :kind,
        :endpoint,
        :auth,
        :provider,
        :lifecycle
      ],
      empty_values: []
    )
    |> validate_tracker_auth()
    |> validate_tracker_provider()
    |> validate_tracker_lifecycle()
  end

  defp validate_tracker_auth(changeset) do
    auth = get_field(changeset, :auth)

    changeset
    |> validate_optional_string_field(auth, "api_key", :"auth.api_key")
    |> validate_optional_string_field(auth, "api_secret", :"auth.api_secret")
  end

  defp validate_tracker_provider(changeset) do
    provider = get_field(changeset, :provider)

    changeset
    |> validate_optional_string_field(provider, "project_slug", :"provider.project_slug")
    |> validate_optional_string_field(provider, "assignee", :"provider.assignee")
    |> validate_optional_map_field(provider, "platform", :"provider.platform")
  end

  defp validate_tracker_lifecycle(changeset) do
    lifecycle = get_field(changeset, :lifecycle)

    changeset
    |> validate_supported_lifecycle_fields(lifecycle)
    |> validate_supported_workflows_by_type_fields(lifecycle)
    |> validate_optional_string_list_field(lifecycle, "active_states", :"lifecycle.active_states")
    |> validate_optional_string_list_field(lifecycle, "terminal_states", :"lifecycle.terminal_states")
    |> validate_optional_map_field(lifecycle, "state_phase_map", :"lifecycle.state_phase_map")
    |> validate_optional_map_field(lifecycle, "raw_state_by_route_key", :"lifecycle.raw_state_by_route_key")
    |> validate_optional_map_field(lifecycle, "policy_by_route_key", :"lifecycle.policy_by_route_key")
    |> validate_optional_map_field(lifecycle, "workflows_by_type", :"lifecycle.workflows_by_type")
  end

  defp validate_supported_lifecycle_fields(changeset, values) when is_map(values) do
    unsupported_field =
      Enum.find(Map.keys(values), fn key ->
        key
        |> normalize_config_field_name()
        |> then(&(not MapSet.member?(@supported_lifecycle_fields, &1)))
      end)

    case unsupported_field do
      nil -> changeset
      field -> add_error(changeset, :lifecycle, "contains unsupported field: #{inspect(field)}")
    end
  end

  defp validate_supported_lifecycle_fields(changeset, _values), do: changeset

  defp validate_supported_workflows_by_type_fields(changeset, values) when is_map(values) do
    case nested_value(values, "workflows_by_type") do
      workflows_by_type when is_map(workflows_by_type) ->
        case unsupported_workflow_by_type_field(workflows_by_type) do
          nil ->
            changeset

          {workitem_type_id, field} ->
            add_error(
              changeset,
              :lifecycle,
              "contains unsupported workflow field for #{inspect(workitem_type_id)}: #{inspect(field)}"
            )
        end

      _other ->
        changeset
    end
  end

  defp validate_supported_workflows_by_type_fields(changeset, _values), do: changeset

  defp unsupported_workflow_by_type_field(workflows_by_type) when is_map(workflows_by_type) do
    Enum.find_value(workflows_by_type, fn {workitem_type_id, workflow} ->
      case workflow do
        workflow_map when is_map(workflow_map) ->
          workflow_map
          |> Map.keys()
          |> Enum.find(fn key ->
            key
            |> normalize_config_field_name()
            |> then(&(not MapSet.member?(@supported_workflow_by_type_fields, &1)))
          end)
          |> case do
            nil -> nil
            field -> {workitem_type_id, field}
          end

        _workflow ->
          nil
      end
    end)
  end

  defp validate_optional_string_field(changeset, values, key, error_field)
       when is_binary(key) and is_atom(error_field) do
    case nested_value(values, key) do
      nil -> changeset
      value when is_binary(value) -> changeset
      _ -> add_error(changeset, error_field, "must be a string")
    end
  end

  defp validate_optional_string_list_field(changeset, values, key, error_field)
       when is_binary(key) and is_atom(error_field) do
    case nested_value(values, key) do
      nil ->
        changeset

      value when is_list(value) ->
        if Enum.all?(value, &is_binary/1) do
          changeset
        else
          add_error(changeset, error_field, "must be a list of strings")
        end

      _ ->
        add_error(changeset, error_field, "must be a list of strings")
    end
  end

  defp validate_optional_map_field(changeset, values, key, error_field)
       when is_binary(key) and is_atom(error_field) do
    case nested_value(values, key) do
      nil -> changeset
      value when is_map(value) -> changeset
      _ -> add_error(changeset, error_field, "must be a map")
    end
  end

  defp nested_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp normalize_config_field_name(key) when is_binary(key), do: key
  defp normalize_config_field_name(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_config_field_name(key), do: key
end
