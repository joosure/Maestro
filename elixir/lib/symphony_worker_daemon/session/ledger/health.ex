defmodule SymphonyWorkerDaemon.Session.Ledger.Health do
  @moduledoc false

  @type t :: %{
          required(:status) => atom(),
          required(:persistence) => atom(),
          optional(:path) => String.t(),
          optional(:last_error) => map()
        }

  @spec ready(String.t() | nil) :: t()
  def ready(nil), do: %{status: :ready, persistence: :disabled}

  def ready(path) when is_binary(path) do
    %{status: :ready, persistence: :enabled, path: path}
  end

  @spec degraded(String.t(), atom(), term()) :: t()
  def degraded(path, operation, reason) when is_binary(path) and is_atom(operation) do
    %{
      status: :degraded,
      persistence: :enabled,
      path: path,
      last_error: %{
        operation: Atom.to_string(operation),
        reason: inspect(reason)
      }
    }
  end

  @spec unavailable() :: t()
  def unavailable, do: %{status: :unavailable, persistence: :unknown}
end
