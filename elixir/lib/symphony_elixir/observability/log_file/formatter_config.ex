defmodule SymphonyElixir.Observability.LogFile.FormatterConfig do
  @moduledoc false

  alias SymphonyElixir.Observability.Formatter, as: ObservabilityFormatter

  @text_time_offset ~c"Z"

  @spec for_format(:json | :text) :: {module() | atom(), map()}
  def for_format(:json), do: {ObservabilityFormatter, %{}}

  def for_format(:text) do
    {:logger_formatter,
     %{
       single_line: true,
       time_offset: @text_time_offset,
       template: text_formatter_template()
     }}
  end

  @spec name(atom()) :: String.t()
  def name(log_format) when is_atom(log_format), do: Atom.to_string(log_format)

  defp text_formatter_template do
    [
      :time,
      " ",
      :level,
      " ",
      {:event, ["event=", :event, " "], []},
      {:component, ["component=", :component, " "], []},
      {:issue_id, ["issue_id=", :issue_id, " "], []},
      {:issue_identifier, ["issue_identifier=", :issue_identifier, " "], []},
      {:request_id, ["request_id=", :request_id, " "], []},
      {:correlation_id, ["correlation_id=", :correlation_id, " "], []},
      {:run_id, ["run_id=", :run_id, " "], []},
      {:session_id, ["session_id=", :session_id, " "], []},
      {:thread_id, ["thread_id=", :thread_id, " "], []},
      {:turn_id, ["turn_id=", :turn_id, " "], []},
      {:tracker_kind, ["tracker_kind=", :tracker_kind, " "], []},
      {:worker_host, ["worker_host=", :worker_host, " "], []},
      {:workspace_path, ["workspace_path=", :workspace_path, " "], []},
      :msg,
      "\n"
    ]
  end
end
