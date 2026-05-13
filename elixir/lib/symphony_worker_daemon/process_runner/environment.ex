defmodule SymphonyWorkerDaemon.ProcessRunner.Environment do
  @moduledoc false

  @spec stringify(map()) :: map()
  def stringify(env) when is_map(env) do
    Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end
end
