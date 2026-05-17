defmodule SymphonyElixir.AgentProvider.Config do
  @moduledoc """
  Provider-neutral effective agent-provider configuration.
  """

  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.Config.InputNormalizer

  @type t :: %__MODULE__{
          kind: String.t() | nil,
          options: map()
        }

  defstruct kind: nil, options: %{}

  @spec new(term()) :: t()
  def new(%__MODULE__{} = config) do
    %__MODULE__{
      kind: normalize_kind(config.kind),
      options: normalize_options(config.options)
    }
  end

  def new(%_{} = config), do: config |> Map.from_struct() |> new()

  def new(config) when is_map(config) do
    normalized = InputNormalizer.normalize_keys(config)

    %__MODULE__{
      kind: normalize_kind(Map.get(normalized, "kind")),
      options: normalize_options(Map.get(normalized, "options", %{}))
    }
  end

  def new(_config), do: %__MODULE__{}

  @spec with_kind(t(), term()) :: t()
  def with_kind(%__MODULE__{} = config, kind), do: %{config | kind: normalize_kind(kind)}

  @spec with_options(t(), term()) :: t()
  def with_options(%__MODULE__{} = config, options), do: %{config | options: normalize_options(options)}

  defp normalize_kind(kind), do: Kinds.normalize(kind)

  defp normalize_options(options) when is_map(options), do: InputNormalizer.normalize_keys(options)
  defp normalize_options(_options), do: %{}
end
