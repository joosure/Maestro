defmodule SymphonyElixir.Config.Schema.AgentProvider do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.AgentProvider.Defaults, as: AgentProviderDefaults
  alias SymphonyElixir.Config.ErrorFormatter

  @primary_key false
  embedded_schema do
    field(:kind, :string, default: AgentProviderDefaults.default_kind())
    field(:options, :map, default: %{})
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:kind, :options], empty_values: [])
    |> validate_required([:kind])
    |> validate_provider_options()
  end

  defp validate_provider_options(changeset) do
    kind = get_field(changeset, :kind)
    options = get_field(changeset, :options)

    cond do
      not is_map(options) ->
        add_error(changeset, :options, "must be a map")

      is_binary(kind) ->
        add_provider_options_result(changeset, kind, AgentProvider.validate_options(kind, options))

      true ->
        changeset
    end
  end

  defp add_provider_options_result(changeset, _kind, :ok), do: changeset

  defp add_provider_options_result(changeset, kind, {:error, %Ecto.Changeset{} = options_changeset}) do
    add_error(
      changeset,
      :options,
      "contains invalid #{kind} options: #{ErrorFormatter.format(options_changeset)}"
    )
  end

  defp add_provider_options_result(changeset, kind, {:error, reason}) do
    add_error(changeset, :options, "contains invalid #{kind} options: #{inspect(reason)}")
  end
end
