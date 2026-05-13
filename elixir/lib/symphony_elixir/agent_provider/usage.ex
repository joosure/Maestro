defmodule SymphonyElixir.AgentProvider.Usage do
  @moduledoc false

  @type t :: %{
          optional(:input_tokens) => non_neg_integer(),
          optional(:output_tokens) => non_neg_integer(),
          optional(:total_tokens) => non_neg_integer(),
          optional(:seconds_running) => non_neg_integer() | float()
        }
end
