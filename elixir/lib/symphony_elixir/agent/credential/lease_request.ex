defmodule SymphonyElixir.Agent.Credential.LeaseRequest do
  @moduledoc false

  @type purpose :: :run | :quota_probe

  @type t :: %__MODULE__{
          provider_kind: String.t(),
          credential_ref: String.t() | nil,
          run_id: String.t() | nil,
          issue_id: String.t() | nil,
          worker_pool: String.t() | nil,
          purpose: purpose()
        }

  defstruct provider_kind: nil,
            credential_ref: nil,
            run_id: nil,
            issue_id: nil,
            worker_pool: nil,
            purpose: :run

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      provider_kind: optional_string(value(attrs, :provider_kind)),
      credential_ref: optional_string(value(attrs, :credential_ref)),
      run_id: optional_string(value(attrs, :run_id)),
      issue_id: optional_string(value(attrs, :issue_id)),
      worker_pool: optional_string(value(attrs, :worker_pool)),
      purpose: normalize_purpose(value(attrs, :purpose))
    }
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp normalize_purpose(:quota_probe), do: :quota_probe
  defp normalize_purpose("quota_probe"), do: :quota_probe
  defp normalize_purpose(_purpose), do: :run

  defp optional_string(nil), do: nil

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp optional_string(_value), do: nil
end
