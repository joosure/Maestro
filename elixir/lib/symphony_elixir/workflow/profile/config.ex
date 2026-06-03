defmodule SymphonyElixir.Workflow.Profile.Config do
  @moduledoc """
  Normalized workflow-profile config selected by repository workflow settings.

  This struct represents the canonical internal form. Repository configuration
  remains string-keyed maps so it can round-trip cleanly through TOML/YAML-like
  sources and prompt facts.
  """

  @enforce_keys [:kind, :version, :options]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          kind: String.t(),
          version: pos_integer(),
          options: map()
        }

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    struct!(__MODULE__, %{
      kind: required_field(attrs, :kind),
      version: required_field(attrs, :version),
      options: required_field(attrs, :options)
    })
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = config) do
    %{
      "kind" => config.kind,
      "version" => config.version,
      "options" => config.options
    }
  end

  @spec fetch(t(), atom()) :: {:ok, term()} | :error
  def fetch(%__MODULE__{} = config, key) when is_atom(key) do
    config
    |> Map.from_struct()
    |> Map.fetch(key)
  end

  def fetch(%__MODULE__{}, _key), do: :error

  defp required_field(map, key) when is_map(map) and is_atom(key) do
    case fetch_field(map, key) do
      {:ok, value} ->
        value

      :error ->
        raise KeyError, key: key, term: map
    end
  end

  defp fetch_field(map, key) when is_map(map) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> {:ok, Map.fetch!(map, key)}
      Map.has_key?(map, string_key) -> {:ok, Map.fetch!(map, string_key)}
      true -> :error
    end
  end
end
