defmodule SymphonyElixir.RepoProvider.LandWatch.PRState do
  @moduledoc false

  @enforce_keys [:number, :head_sha]
  defstruct [:number, :url, :head_sha, :mergeable, :merge_state]

  @type t :: %__MODULE__{
          number: integer() | String.t(),
          url: String.t() | nil,
          head_sha: String.t(),
          mergeable: String.t() | nil,
          merge_state: String.t() | nil
        }

  @spec from_payload(map()) :: {:ok, t()} | {:error, term()}
  def from_payload(payload) when is_map(payload) do
    number = field_value(payload, "number")
    head_sha = field_value(payload, "headRefOid")

    cond do
      is_nil(number) ->
        {:error, {:invalid_pr_view_payload, :missing_number}}

      not is_binary(head_sha) or head_sha == "" ->
        {:error, {:invalid_pr_view_payload, :missing_head_sha}}

      true ->
        {:ok,
         %__MODULE__{
           number: number,
           url: field_value(payload, "url"),
           head_sha: head_sha,
           mergeable: field_value(payload, "mergeable"),
           merge_state: field_value(payload, "mergeStateStatus")
         }}
    end
  end

  @spec merge_conflicting?(t()) :: boolean()
  def merge_conflicting?(%__MODULE__{mergeable: "CONFLICTING"}), do: true
  def merge_conflicting?(%__MODULE__{merge_state: "DIRTY"}), do: true
  def merge_conflicting?(_pr), do: false

  defp field_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp map_get_existing_atom(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end
end
