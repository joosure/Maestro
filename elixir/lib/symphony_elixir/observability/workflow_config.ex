defmodule SymphonyElixir.Observability.WorkflowConfig do
  @moduledoc """
  Applies observability settings from a loaded workflow configuration.
  """

  alias SymphonyElixir.Config.Schema
  alias SymphonyElixir.Observability.{EventStore, Redaction}
  alias SymphonyElixir.Observability.LogFile
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @spec configure_from_workflow(Path.t(), map(), map()) :: :ok
  def configure_from_workflow(path, %{config: config}, event_fields)
      when is_binary(path) and is_map(config) and is_map(event_fields) do
    case Schema.parse(config) do
      {:ok, settings} ->
        LogFile.configure_from_observability(settings.observability)
        EventStore.configure_from_observability(settings.observability)
        Redaction.configure_from_observability(settings.observability)

      {:error, {:invalid_workflow_config, message}} ->
        ObsLogger.emit(
          :warning,
          :workflow_observability_config_invalid,
          Map.merge(event_fields, %{
            error: message,
            result_summary: "observability_config_reconfigure_skipped",
            message: "workflow_observability_config_invalid workflow_path=#{path} result=observability_config_reconfigure_skipped error=#{message}"
          })
        )

        :ok
    end
  end

  def configure_from_workflow(_path, _workflow, _event_fields), do: :ok
end
