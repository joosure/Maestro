defmodule SymphonyWorkerDaemon.CapacityManager.Options do
  @moduledoc false

  @spec positive_integer(term(), pos_integer()) :: pos_integer()
  def positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  def positive_integer(_value, default), do: default

  @spec optional_positive_integer(term()) :: pos_integer() | nil
  def optional_positive_integer(value) when is_integer(value) and value > 0, do: value
  def optional_positive_integer(_value), do: nil
end
