defmodule SymphonyElixir.Storage.Backup.DisabledBackend do
  @moduledoc false

  @behaviour SymphonyElixir.Storage.Backup

  alias SymphonyElixir.Storage.ErrorCodes

  @impl true
  def create(_opts) do
    {:error,
     %{
       code: ErrorCodes.backup_unavailable(),
       message: "Storage backup backend is not configured.",
       reason: :backup_backend_not_configured
     }}
  end
end
