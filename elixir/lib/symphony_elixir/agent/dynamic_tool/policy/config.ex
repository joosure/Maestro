defmodule SymphonyElixir.Agent.DynamicTool.Policy.Config do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Metadata
  alias SymphonyElixir.Agent.DynamicTool.Policy.Error

  @side_effect_classes Metadata.Contract.side_effect_classes()

  @enforce_keys [:allowed_side_effects]
  defstruct allowed_side_effects: @side_effect_classes,
            allow_operator_tools?: false,
            exposure: nil

  @type exposure :: :diagnostics | :all | nil

  @type t :: %__MODULE__{
          allowed_side_effects: [String.t()],
          allow_operator_tools?: boolean(),
          exposure: exposure()
        }

  @spec default() :: t()
  def default, do: %__MODULE__{allowed_side_effects: @side_effect_classes}

  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(attrs) when is_list(attrs) do
    with {:ok, allowed_side_effects} <-
           attrs |> Keyword.get(:allowed_side_effects, @side_effect_classes) |> normalize_allowed_side_effects(),
         {:ok, allow_operator_tools?} <-
           attrs |> Keyword.get(:allow_operator_tools?, false) |> normalize_allow_operator_tools(),
         {:ok, exposure} <-
           attrs |> Keyword.get(:exposure, nil) |> normalize_exposure() do
      {:ok,
       %__MODULE__{
         allowed_side_effects: allowed_side_effects,
         allow_operator_tools?: allow_operator_tools?,
         exposure: exposure
       }}
    end
  end

  def new(_attrs), do: {:error, Error.invalid_policy_config(:non_keyword_config)}

  @spec new!(keyword()) :: t()
  def new!(attrs) when is_list(attrs) do
    case new(attrs) do
      {:ok, config} -> config
      {:error, error} -> raise ArgumentError, "invalid dynamic tool policy config: #{inspect(error)}"
    end
  end

  @spec from_opts(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def from_opts(opts) when is_list(opts) do
    with {:ok, config} <- policy_config(opts),
         {:ok, exposure} <- opts |> Keyword.get(:dynamic_tool_exposure, config.exposure) |> normalize_exposure() do
      {:ok, %{config | exposure: exposure}}
    end
  end

  def from_opts(_opts), do: {:error, Error.invalid_policy_config(:non_keyword_opts)}

  @spec normalize(term()) :: {:ok, t()} | {:error, Error.t()}
  def normalize(%__MODULE__{} = config), do: new(Map.from_struct(config) |> Keyword.new())
  def normalize(_config), do: {:error, Error.invalid_policy_config(:non_policy_config)}

  defp policy_config(opts) do
    case Keyword.fetch(opts, :dynamic_tool_policy) do
      {:ok, %__MODULE__{} = config} -> normalize(config)
      {:ok, invalid} -> {:error, Error.invalid_policy_config(invalid)}
      :error -> configured_policy()
    end
  end

  defp configured_policy do
    case Application.get_env(:symphony_elixir, :dynamic_tool_policy) do
      nil -> {:ok, default()}
      %__MODULE__{} = config -> normalize(config)
      invalid -> {:error, Error.invalid_policy_config(invalid)}
    end
  end

  defp normalize_allowed_side_effects(values) when is_list(values) do
    if Enum.all?(values, &(&1 in @side_effect_classes)) do
      {:ok, Enum.uniq(values)}
    else
      {:error, Error.invalid_allowed_side_effects(values)}
    end
  end

  defp normalize_allowed_side_effects(value), do: {:error, Error.invalid_allowed_side_effects(value)}

  defp normalize_allow_operator_tools(value) when is_boolean(value), do: {:ok, value}
  defp normalize_allow_operator_tools(value), do: {:error, Error.invalid_allow_operator_tools(value)}

  defp normalize_exposure(nil), do: {:ok, nil}
  defp normalize_exposure(:diagnostics), do: {:ok, :diagnostics}
  defp normalize_exposure(:all), do: {:ok, :all}
  defp normalize_exposure(value), do: {:error, Error.invalid_exposure(value)}
end
