defmodule SymphonyElixir.Config.Schema.Worker do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias SymphonyElixir.Platform.SSH

  @primary_key false
  embedded_schema do
    field(:ssh_hosts, {:array, :string}, default: [])
    field(:max_concurrent_agents_per_host, :integer)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:ssh_hosts, :max_concurrent_agents_per_host], empty_values: [])
    |> normalize_ssh_hosts(attrs)
    |> validate_number(:max_concurrent_agents_per_host, greater_than: 0)
    |> validate_capacity_requires_hosts()
  end

  defp normalize_ssh_hosts(changeset, attrs) do
    case fetch_input_value(attrs, :ssh_hosts) do
      :not_provided ->
        changeset

      ssh_hosts when is_list(ssh_hosts) ->
        case normalize_host_entries(ssh_hosts) do
          {:ok, normalized_hosts} ->
            if normalized_hosts == [] do
              add_error(changeset, :ssh_hosts, "must not be empty")
            else
              put_change(changeset, :ssh_hosts, normalized_hosts)
            end

          {:error, message} ->
            add_error(changeset, :ssh_hosts, message)
        end

      _other ->
        add_error(changeset, :ssh_hosts, "must be a list of SSH host strings")
    end
  end

  defp fetch_input_value(attrs, field) when is_map(attrs) do
    string_field = Atom.to_string(field)

    cond do
      Map.has_key?(attrs, string_field) -> Map.get(attrs, string_field)
      Map.has_key?(attrs, field) -> Map.get(attrs, field)
      true -> :not_provided
    end
  end

  defp normalize_host_entries(ssh_hosts) when is_list(ssh_hosts) do
    case Enum.reduce_while(ssh_hosts |> Enum.with_index(1), {[], MapSet.new()}, fn {raw_host, index}, {normalized, seen} ->
           case SSH.normalize_host_entry(raw_host) do
             {:ok, host} ->
               if MapSet.member?(seen, host) do
                 {:halt, {:error, "contains duplicate entry #{inspect(host)}"}}
               else
                 {:cont, {normalized ++ [host], MapSet.put(seen, host)}}
               end

             {:error, :blank} ->
               {:halt, {:error, "contains blank entry at index #{index}"}}

             {:error, reason} ->
               {:halt, {:error, "contains invalid entry at index #{index}: #{Atom.to_string(reason)}"}}
           end
         end) do
      {:error, _message} = error -> error
      {normalized, _seen} -> {:ok, normalized}
    end
  end

  defp validate_capacity_requires_hosts(changeset) do
    case get_change(changeset, :max_concurrent_agents_per_host) do
      nil ->
        changeset

      _limit ->
        case get_field(changeset, :ssh_hosts) do
          hosts when is_list(hosts) and hosts != [] ->
            changeset

          _ ->
            add_error(
              changeset,
              :max_concurrent_agents_per_host,
              "requires worker.ssh_hosts to be configured and valid"
            )
        end
    end
  end
end
