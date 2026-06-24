defmodule SymphonyElixir.Workflow.Extension.Runtime.Result do
  @moduledoc """
  Stable runtime output envelope returned by workflow extensions.

  Extensions return their own private runtime state plus typed commands for the
  platform to execute. They do not replace the platform runtime state map.
  """

  alias SymphonyElixir.Workflow.Extension.{Diagnostics, ErrorCodes}
  alias SymphonyElixir.Workflow.Extension.Runtime.Command, as: RuntimeCommand

  @field_defaults [extension_state: nil, commands: [], events: [], decisions: [], metadata: %{}]
  @field_keys Keyword.keys(@field_defaults)
  @allowed_keys @field_keys
  @external_field_names Enum.map(@field_keys, &Atom.to_string/1)
  @external_key_map Map.new(@field_keys, &{Atom.to_string(&1), &1})

  @enforce_keys [:extension_state]
  defstruct @field_defaults

  @type t :: %__MODULE__{
          extension_state: map(),
          commands: [RuntimeCommand.t()],
          events: [map()],
          decisions: [map()],
          metadata: map()
        }

  @spec field_keys() :: [atom()]
  def field_keys, do: @field_keys

  @spec external_field_names() :: [String.t()]
  def external_field_names, do: @external_field_names

  @spec replace_extension_state(map(), keyword() | map()) :: {:ok, t()} | {:error, map()}
  def replace_extension_state(extension_state, attrs \\ []) when is_map(extension_state) do
    attrs
    |> Map.new()
    |> Map.put(:extension_state, extension_state)
    |> new()
  end

  @spec replace_extension_state!(map(), keyword() | map()) :: t()
  def replace_extension_state!(extension_state, attrs \\ []) when is_map(extension_state) do
    case replace_extension_state(extension_state, attrs) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, format_error(reason)
    end
  end

  @spec new(map()) :: {:ok, t()} | {:error, map()}
  def new(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    with :ok <- validate_known_keys(attrs),
         {:ok, extension_state} <- required_map(attrs, :extension_state),
         {:ok, commands} <- optional_commands(attrs, :commands),
         {:ok, events} <- optional_maps(attrs, :events),
         {:ok, decisions} <- optional_maps(attrs, :decisions),
         {:ok, metadata} <- optional_map(attrs, :metadata) do
      {:ok,
       %__MODULE__{
         extension_state: extension_state,
         commands: commands,
         events: events,
         decisions: decisions,
         metadata: metadata
       }}
    end
  end

  def new(attrs), do: {:error, invalid(:result_not_a_map, attrs)}

  defp normalize_keys(attrs) do
    Enum.into(attrs, %{}, fn {key, value} ->
      {Map.get(@external_key_map, key, key), value}
    end)
  end

  defp validate_known_keys(attrs) do
    unknown_keys = attrs |> Map.keys() |> Enum.reject(&(&1 in @allowed_keys))

    case unknown_keys do
      [] -> :ok
      keys -> {:error, invalid(:unknown_fields, keys)}
    end
  end

  defp required_map(attrs, key) do
    case Map.get(attrs, key) do
      value when is_map(value) -> {:ok, value}
      value -> {:error, invalid({:invalid_map, key}, value)}
    end
  end

  defp optional_map(attrs, key) do
    case Map.get(attrs, key, %{}) do
      value when is_map(value) -> {:ok, value}
      value -> {:error, invalid({:invalid_map, key}, value)}
    end
  end

  defp optional_commands(attrs, key) do
    case Map.get(attrs, key, []) do
      value when is_list(value) ->
        if Enum.all?(value, &RuntimeCommand.valid?/1) do
          {:ok, value}
        else
          {:error, invalid({:invalid_commands, key}, value)}
        end

      value ->
        {:error, invalid({:invalid_list, key}, value)}
    end
  end

  defp optional_maps(attrs, key) do
    case Map.get(attrs, key, []) do
      value when is_list(value) ->
        if Enum.all?(value, &is_map/1) do
          {:ok, value}
        else
          {:error, invalid({:invalid_map_list, key}, value)}
        end

      value ->
        {:error, invalid({:invalid_list, key}, value)}
    end
  end

  defp invalid(reason, value) do
    %{
      code: ErrorCodes.runtime_extension_failed(),
      message: "Workflow runtime extension result is invalid.",
      reason: normalized_reason(reason)
    }
    |> Map.merge(invalid_diagnostic(reason, value))
  end

  defp normalized_reason({reason, _key}), do: reason
  defp normalized_reason(reason), do: reason

  defp invalid_diagnostic(:unknown_fields, fields), do: %{fields: Enum.map(fields, &inspect/1)}

  defp invalid_diagnostic({:invalid_commands, key}, commands) when is_list(commands) do
    %{
      field: key,
      commands: Enum.map(commands, &RuntimeCommand.diagnostic/1)
    }
  end

  defp invalid_diagnostic({_reason, key}, value), do: %{field: key, value_type: Diagnostics.type_name(value)}
  defp invalid_diagnostic(_reason, value), do: %{value_type: Diagnostics.type_name(value)}

  defp format_error(reason) when is_map(reason) do
    reason_text =
      reason
      |> Map.get(:reason)
      |> format_reason()

    field_text =
      case Map.get(reason, :field) do
        field when is_atom(field) -> " field=#{field}"
        _field -> ""
      end

    "Workflow runtime extension result is invalid: reason=#{reason_text}#{field_text}"
  end

  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(_reason), do: "invalid"
end
