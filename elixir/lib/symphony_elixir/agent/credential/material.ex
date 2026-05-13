defmodule SymphonyElixir.Agent.Credential.Material do
  @moduledoc false

  @type t :: %__MODULE__{
          env: map(),
          auth_metadata: map(),
          summary: map(),
          cleanup: [term()]
        }

  defstruct env: %{},
            auth_metadata: %{},
            summary: %{},
            cleanup: []

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      env: normalize_map(value(attrs, :env)),
      auth_metadata: normalize_map(value(attrs, :auth_metadata)),
      summary: normalize_map(value(attrs, :summary)),
      cleanup: normalize_list(value(attrs, :cleanup))
    }
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_map), do: %{}

  defp normalize_list(list) when is_list(list), do: list
  defp normalize_list(_list), do: []
end
