defmodule SymphonyElixir.RepoProvider.Result do
  @moduledoc false

  defstruct [
    :mode,
    :payload,
    json_fields: nil,
    jq: nil,
    query_label: "repo-provider",
    exit_code: 0
  ]

  @type t :: %__MODULE__{
          mode: :json | :text,
          payload: term(),
          json_fields: nil | [String.t()],
          jq: nil | String.t(),
          query_label: String.t(),
          exit_code: non_neg_integer()
        }
end
