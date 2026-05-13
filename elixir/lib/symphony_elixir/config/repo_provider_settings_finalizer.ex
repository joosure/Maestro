defmodule SymphonyElixir.Config.RepoProviderSettingsFinalizer do
  @moduledoc false

  alias SymphonyElixir.Config.InputNormalizer
  alias SymphonyElixir.RepoProvider

  @spec finalize(struct()) :: struct()
  def finalize(repo) do
    remote = repo.remote || %SymphonyElixir.Config.Schema.Repo.Remote{}
    branch = repo.branch || %SymphonyElixir.Config.Schema.Repo.Branch{}
    provider = repo.provider || %SymphonyElixir.Config.Schema.Repo.Provider{}
    kind = InputNormalizer.resolve_string_setting(provider.kind, RepoProvider.default_kind())
    defaults = RepoProvider.defaults(kind)
    default_provider = normalize_optional_map(defaults[:provider])
    env_vars = normalize_optional_map(defaults[:env_vars])

    resolved_provider =
      default_provider
      |> merge_section(explicit_provider_input(provider))
      |> finalize_section(Map.get(env_vars, "provider"))

    required_pr_label =
      resolved_provider
      |> resolve_required_pr_label()
      |> InputNormalizer.resolve_optional_string_setting()

    options =
      resolved_provider
      |> map_field("options")
      |> normalize_optional_map()
      |> Map.delete("required_pr_label")
      |> maybe_put("required_pr_label", required_pr_label)
      |> compact_map()

    %{
      repo
      | path: InputNormalizer.resolve_string_setting(repo.path, "repo"),
        base_branch: InputNormalizer.resolve_string_setting(repo.base_branch, "main"),
        remote: %{
          remote
          | name: InputNormalizer.resolve_string_setting(remote.name, "origin"),
            url: InputNormalizer.resolve_optional_string_setting(remote.url)
        },
        branch: %{
          branch
          | work_prefix: InputNormalizer.resolve_optional_string_setting(branch.work_prefix)
        },
        provider: %{
          provider
          | kind: kind,
            repository: resolved_provider |> map_field("repository") |> InputNormalizer.resolve_optional_string_setting(),
            api_base_url: resolved_provider |> map_field("api_base_url") |> InputNormalizer.resolve_optional_string_setting(),
            web_base_url: resolved_provider |> map_field("web_base_url") |> InputNormalizer.resolve_optional_string_setting(),
            options: options
        }
    }
  end

  defp explicit_provider_input(provider) do
    %{}
    |> maybe_put("repository", provider.repository)
    |> maybe_put("api_base_url", provider.api_base_url)
    |> maybe_put("web_base_url", provider.web_base_url)
    |> maybe_put_map("options", provider.options)
  end

  defp resolve_required_pr_label(provider) when is_map(provider) do
    provider
    |> map_field("options")
    |> map_field("required_pr_label")
  end

  defp resolve_required_pr_label(_provider), do: nil

  defp normalize_default_map(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> normalize_default_map()
  end

  defp normalize_default_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested}, acc ->
      Map.put(acc, normalize_key(key), normalize_default_map(nested))
    end)
  end

  defp normalize_default_map(value) when is_list(value), do: Enum.map(value, &normalize_default_map/1)
  defp normalize_default_map(value), do: value

  defp normalize_optional_map(value) when is_map(value), do: normalize_default_map(value)
  defp normalize_optional_map(_value), do: %{}

  defp merge_section(defaults, section) when is_map(defaults) and is_map(section) do
    Map.merge(defaults, normalize_default_map(section))
  end

  defp finalize_section(values, env_vars) when is_map(values) do
    values
    |> resolve_env_references()
    |> apply_env_var_defaults(env_vars)
  end

  defp resolve_env_references(values) when is_map(values) do
    Enum.reduce(values, %{}, fn {key, value}, acc ->
      Map.put(acc, key, resolve_env_references(value))
    end)
  end

  defp resolve_env_references(value) when is_list(value), do: Enum.map(value, &resolve_env_references/1)

  defp resolve_env_references(value) when is_binary(value) do
    case env_reference_name(value) do
      {:ok, env_name} -> System.get_env(env_name)
      :error -> value
    end
  end

  defp resolve_env_references(value), do: value

  defp apply_env_var_defaults(values, env_vars)
       when is_map(values) and is_map(env_vars) do
    Enum.reduce(env_vars, values, fn {key, env_config}, acc ->
      normalized_key = normalize_key(key)
      current_value = Map.get(acc, normalized_key)

      resolved_value =
        case env_config do
          nested_env_vars when is_map(nested_env_vars) ->
            current_value
            |> normalize_optional_map()
            |> apply_env_var_defaults(nested_env_vars)

          env_name when is_binary(env_name) ->
            apply_env_var_default(current_value, env_name)

          _ ->
            current_value
        end

      Map.put(acc, normalized_key, resolved_value)
    end)
  end

  defp apply_env_var_defaults(values, _env_vars), do: values

  defp apply_env_var_default(nil, env_name) when is_binary(env_name), do: System.get_env(env_name)
  defp apply_env_var_default(current_value, _env_name), do: current_value

  defp env_reference_name("$" <> env_name) do
    if String.match?(env_name, ~r/^[A-Za-z_][A-Za-z0-9_]*$/) do
      {:ok, env_name}
    else
      :error
    end
  end

  defp env_reference_name(_value), do: :error

  defp compact_map(values) when is_map(values) do
    Enum.reduce(values, %{}, fn
      {_key, nil}, acc ->
        acc

      {_key, value}, acc when is_map(value) and map_size(value) == 0 ->
        acc

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp map_field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp map_field(_map, _key), do: nil

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp normalize_key(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_key(value), do: to_string(value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_map(map, _key, value) when not is_map(value) or map_size(value) == 0, do: map
  defp maybe_put_map(map, key, value), do: Map.put(map, key, normalize_default_map(value))
end
