defmodule SymphonyElixir.Workflow.Extension.ToolResultRecorder do
  @moduledoc """
  Behaviour for workflow extension-owned Dynamic Tool result recorders.

  Recorders consume provider-neutral Dynamic Tool execution results through a
  platform dispatcher. Concrete extensions own the business interpretation of
  those results; tracker, repo, and repo-provider sources remain independent of
  concrete workflow extension modules.
  """

  @type recorder_id :: String.t()
  @type source_kind :: String.t() | atom() | nil
  @type tool_result :: {:success, term()} | {:failure, term()} | {:error, term()} | term()

  @callback id() :: recorder_id()

  @callback record_tool_result(
              source_kind(),
              term(),
              String.t() | nil,
              term(),
              tool_result(),
              keyword()
            ) :: :ok | {:error, term()}
end
