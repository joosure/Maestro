defmodule SymphonyElixir.Config.Schema.AgentRuntime do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  defmodule WorkerDaemon do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:endpoint, :string)
      field(:endpoints, {:array, :map}, default: [])
      field(:pools, :map, default: %{})
      field(:token_env, :string)
      field(:timeout_ms, :integer)
      field(:required_features, {:array, :string}, default: [])
      field(:health_cache_ttl_ms, :integer)
      field(:circuit_ttl_ms, :integer)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      attrs = normalize_attrs(attrs)

      schema
      |> cast(attrs, [:endpoint, :endpoints, :pools, :token_env, :timeout_ms, :required_features, :health_cache_ttl_ms, :circuit_ttl_ms], empty_values: [])
      |> validate_optional_endpoint(:endpoint)
      |> validate_endpoint_entries(:endpoints)
      |> validate_endpoint_pools(:pools)
      |> validate_optional_env_name(:token_env)
      |> validate_number(:timeout_ms, greater_than: 0)
      |> validate_number(:health_cache_ttl_ms, greater_than_or_equal_to: 0)
      |> validate_number(:circuit_ttl_ms, greater_than_or_equal_to: 0)
      |> validate_required_features()
    end

    defp normalize_attrs(attrs) when is_map(attrs) do
      attrs
      |> normalize_endpoint_entries_attr("endpoints")
      |> normalize_pool_entries_attr("pools")
    end

    defp normalize_attrs(_attrs), do: %{}

    defp normalize_endpoint_entries_attr(attrs, key) do
      case fetch_config_value(attrs, key) do
        :not_provided -> attrs
        value -> put_config_value(attrs, key, normalize_endpoint_entries(value))
      end
    end

    defp normalize_pool_entries_attr(attrs, key) do
      case fetch_config_value(attrs, key) do
        :not_provided -> attrs
        value -> put_config_value(attrs, key, normalize_endpoint_pools(value))
      end
    end

    defp normalize_endpoint_entries(nil), do: []

    defp normalize_endpoint_entries(value) when is_binary(value) do
      value
      |> String.split([",", "\n"], trim: true)
      |> Enum.map(&normalize_endpoint_entry/1)
    end

    defp normalize_endpoint_entries(values) when is_list(values) do
      Enum.map(values, &normalize_endpoint_entry/1)
    end

    defp normalize_endpoint_entries(value), do: [normalize_endpoint_entry(value)]

    defp normalize_endpoint_entry(value) when is_binary(value), do: %{"endpoint" => value}

    defp normalize_endpoint_entry(value) when is_map(value) do
      endpoint = config_value(value, "endpoint") || config_value(value, "url")
      worker_id = config_value(value, "worker_id")
      endpoint_id = config_value(value, "id") || config_value(value, "endpoint_id")

      %{
        "endpoint" => endpoint,
        "worker_id" => worker_id,
        "id" => endpoint_id
      }
      |> Enum.reject(fn {_key, entry_value} -> is_nil(entry_value) end)
      |> Map.new()
    end

    defp normalize_endpoint_entry(_value), do: %{}

    defp normalize_endpoint_pools(nil), do: %{}

    defp normalize_endpoint_pools(pools) when is_map(pools) do
      pools
      |> Enum.reduce(%{}, fn {pool_name, entries}, normalized ->
        Map.put(normalized, to_string(pool_name), normalize_endpoint_entries(entries))
      end)
    end

    defp normalize_endpoint_pools(_pools), do: %{}

    defp validate_optional_endpoint(changeset, field) when is_atom(field) do
      validate_change(changeset, field, fn ^field, value ->
        case validate_endpoint_url(value) do
          :ok -> []
          {:error, message} -> [{field, message}]
        end
      end)
    end

    defp validate_endpoint_entries(changeset, field) when is_atom(field) do
      validate_change(changeset, field, fn ^field, entries ->
        entries
        |> List.wrap()
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {entry, index} ->
          validate_endpoint_entry(field, entry, index)
        end)
      end)
    end

    defp validate_endpoint_pools(changeset, field) when is_atom(field) do
      validate_change(changeset, field, fn ^field, pools ->
        cond do
          not is_map(pools) ->
            [{field, "must be a map of worker pool names to endpoint entries"}]

          true ->
            Enum.flat_map(pools, &validate_endpoint_pool(field, &1))
        end
      end)
    end

    defp validate_endpoint_pool(field, {pool_name, entries}) do
      cond do
        not non_blank_string?(pool_name) ->
          [{field, "contains a blank worker pool name"}]

        not is_list(entries) ->
          [{field, "pool #{inspect(pool_name)} must be a list of endpoint entries"}]

        true ->
          validate_pool_endpoint_entries(field, pool_name, entries)
      end
    end

    defp validate_pool_endpoint_entries(field, pool_name, entries) do
      entries
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {entry, index} ->
        validate_endpoint_entry(field, entry, index, pool_name)
      end)
    end

    defp validate_endpoint_entry(field, entry, index, pool_name \\ nil)

    defp validate_endpoint_entry(field, entry, index, pool_name) when is_map(entry) do
      context = endpoint_entry_context(index, pool_name)
      supported_keys = ["endpoint", "worker_id", "id"]
      unsupported_keys = entry |> Map.keys() |> Enum.map(&to_string/1) |> Enum.reject(&(&1 in supported_keys))

      cond do
        unsupported_keys != [] ->
          [{field, "#{context} contains unsupported fields: #{Enum.join(unsupported_keys, ", ")}"}]

        not non_blank_string?(Map.get(entry, "endpoint")) ->
          [{field, "#{context} requires a non-blank endpoint"}]

        true ->
          case validate_endpoint_url(Map.get(entry, "endpoint")) do
            :ok -> validate_optional_entry_strings(field, entry, context)
            {:error, message} -> [{field, "#{context} #{message}"}]
          end
      end
    end

    defp validate_endpoint_entry(field, _entry, index, pool_name) do
      [{field, "#{endpoint_entry_context(index, pool_name)} must be a string or map"}]
    end

    defp validate_optional_entry_strings(field, entry, context) do
      ["worker_id", "id"]
      |> Enum.flat_map(fn key ->
        case Map.get(entry, key) do
          nil -> []
          value when is_binary(value) and value != "" -> []
          _value -> [{field, "#{context} #{key} must be a non-blank string"}]
        end
      end)
    end

    defp validate_optional_env_name(changeset, field) when is_atom(field) do
      validate_change(changeset, field, fn ^field, value ->
        cond do
          is_nil(value) ->
            []

          is_binary(value) and String.match?(value, ~r/^[A-Za-z_][A-Za-z0-9_]*$/) ->
            []

          true ->
            [{field, "must be an environment variable name"}]
        end
      end)
    end

    defp validate_required_features(changeset) do
      validate_change(changeset, :required_features, fn :required_features, features ->
        if Enum.all?(features, &non_blank_string?/1) do
          []
        else
          [required_features: "must be a list of non-blank strings"]
        end
      end)
    end

    defp validate_endpoint_url(value) when is_binary(value) do
      uri = URI.parse(value)

      cond do
        String.trim(value) == "" ->
          {:error, "must be a non-blank endpoint URL"}

        uri.scheme not in ["http", "https"] ->
          {:error, "must use http or https scheme"}

        not is_binary(uri.host) or uri.host == "" ->
          {:error, "must include a host"}

        is_binary(uri.userinfo) ->
          {:error, "must not include userinfo"}

        is_binary(uri.query) ->
          {:error, "must not include a query string"}

        is_binary(uri.fragment) ->
          {:error, "must not include a fragment"}

        true ->
          :ok
      end
    end

    defp validate_endpoint_url(_value), do: {:error, "must be an endpoint URL string"}

    defp endpoint_entry_context(index, nil), do: "endpoint entry #{index}"
    defp endpoint_entry_context(index, pool_name), do: "endpoint entry #{index} in pool #{inspect(pool_name)}"

    defp non_blank_string?(value), do: is_binary(value) and String.trim(value) != ""

    defp fetch_config_value(map, key) when is_map(map) and is_binary(key) do
      atom_key = String.to_existing_atom(key)

      cond do
        Map.has_key?(map, key) -> Map.get(map, key)
        Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
        true -> :not_provided
      end
    rescue
      ArgumentError ->
        if Map.has_key?(map, key), do: Map.get(map, key), else: :not_provided
    end

    defp put_config_value(map, key, value) when is_map(map) and is_binary(key) do
      cond do
        Map.has_key?(map, key) ->
          Map.put(map, key, value)

        true ->
          atom_key = String.to_existing_atom(key)

          if Map.has_key?(map, atom_key) do
            Map.put(map, atom_key, value)
          else
            Map.put(map, key, value)
          end
      end
    rescue
      ArgumentError -> Map.put(map, key, value)
    end

    defp config_value(map, key) when is_map(map) and is_binary(key) do
      atom_key = String.to_existing_atom(key)
      Map.get(map, key) || Map.get(map, atom_key)
    rescue
      ArgumentError -> Map.get(map, key)
    end
  end

  @primary_key false
  embedded_schema do
    field(:placement, :string)
    field(:worker_pool, :string)
    field(:worker_host, :string)
    field(:remote_workspace_path, :string)
    field(:env, :map, default: %{})
    embeds_one(:worker_daemon, WorkerDaemon, on_replace: :update, defaults_to_struct: true)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:placement, :worker_pool, :worker_host, :remote_workspace_path, :env], empty_values: [])
    |> validate_inclusion(:placement, ["local", "ssh", "worker_daemon"])
    |> validate_optional_string(:worker_pool)
    |> validate_optional_string(:worker_host)
    |> validate_optional_string(:remote_workspace_path)
    |> validate_env_map()
    |> cast_embed(:worker_daemon, with: &WorkerDaemon.changeset/2)
  end

  defp validate_optional_string(changeset, field) when is_atom(field) do
    validate_change(changeset, field, fn ^field, value ->
      if is_binary(value) and String.trim(value) != "" do
        []
      else
        [{field, "must be a non-blank string"}]
      end
    end)
  end

  defp validate_env_map(changeset) do
    validate_change(changeset, :env, fn :env, env ->
      cond do
        not is_map(env) ->
          [env: "must be a map"]

        Enum.all?(env, fn {key, value} -> is_binary(key) and is_binary(value) end) ->
          []

        true ->
          [env: "must contain only string keys and string values"]
      end
    end)
  end
end
