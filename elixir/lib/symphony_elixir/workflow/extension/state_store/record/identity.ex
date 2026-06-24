defmodule SymphonyElixir.Workflow.Extension.StateStore.Record.Identity do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Canonical

  @spec scope_key(map()) :: {:ok, String.t()} | {:error, map()}
  def scope_key(workflow_scope), do: Canonical.state_store_scope_key(workflow_scope)

  @spec record_id(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def record_id(extension_id, workflow_scope_key, state_type, state_key) do
    [extension_id, workflow_scope_key, state_type, state_key]
    |> Enum.join(<<0>>)
    |> hash_binary()
  end

  defp hash_binary(binary) do
    :crypto.hash(:sha256, binary)
    |> Base.encode16(case: :lower)
  end
end
