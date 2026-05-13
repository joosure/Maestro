defmodule SymphonyElixir.Config.Schema.Repo do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  defmodule Remote do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false

    embedded_schema do
      field(:name, :string, default: "origin")
      field(:url, :string)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:name, :url], empty_values: [])
      |> validate_required([:name])
    end
  end

  defmodule Branch do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false

    embedded_schema do
      field(:work_prefix, :string)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:work_prefix], empty_values: [])
    end
  end

  defmodule Provider do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false

    embedded_schema do
      field(:kind, :string, default: "github")
      field(:repository, :string)
      field(:api_base_url, :string)
      field(:web_base_url, :string)
      field(:options, :map, default: %{})
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:kind, :repository, :api_base_url, :web_base_url, :options], empty_values: [])
      |> reject_removed_github_settings(attrs)
    end

    defp reject_removed_github_settings(changeset, attrs) when is_map(attrs) do
      if Map.has_key?(attrs, "github") || Map.has_key?(attrs, :github) do
        add_error(
          changeset,
          :github,
          "has been removed; use repo.provider.options.required_pr_label instead"
        )
      else
        changeset
      end
    end
  end

  @primary_key false
  embedded_schema do
    field(:path, :string, default: "repo")
    field(:base_branch, :string, default: "main")
    embeds_one(:remote, Remote, on_replace: :update, defaults_to_struct: true)
    embeds_one(:branch, Branch, on_replace: :update, defaults_to_struct: true)
    embeds_one(:provider, Provider, on_replace: :update, defaults_to_struct: true)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:path, :base_branch], empty_values: [])
    |> cast_embed(:remote, with: &Remote.changeset/2)
    |> cast_embed(:branch, with: &Branch.changeset/2)
    |> cast_embed(:provider, with: &Provider.changeset/2)
    |> reject_removed_required_pr_label_key(attrs)
    |> validate_required([:path, :base_branch])
  end

  defp reject_removed_required_pr_label_key(changeset, attrs) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, "required_pr_label") ->
        add_error(
          changeset,
          :required_pr_label,
          "has been removed; use repo.provider.options.required_pr_label instead"
        )

      Map.has_key?(attrs, :required_pr_label) ->
        add_error(
          changeset,
          :required_pr_label,
          "has been removed; use repo.provider.options.required_pr_label instead"
        )

      true ->
        changeset
    end
  end
end
