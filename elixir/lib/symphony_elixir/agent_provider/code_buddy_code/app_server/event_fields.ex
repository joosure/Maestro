defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.AppServer.EventFields do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.AppServer.EventFields, as: AppServerEventFields
  alias SymphonyElixir.AgentProvider.Kinds

  @provider_kind Kinds.codebuddy_code()

  @spec build(Path.t() | nil, String.t() | nil, map() | nil, map()) :: map()
  def build(workspace, worker_host, issue, extra \\ %{}) when is_map(extra) do
    AppServerEventFields.build(base_fields(), workspace, worker_host, issue, extra, compact_issue_fields?: false)
  end

  @spec monotonic_ms() :: integer()
  def monotonic_ms, do: System.monotonic_time(:millisecond)

  @spec elapsed_ms(integer()) :: non_neg_integer()
  def elapsed_ms(started_at_ms) when is_integer(started_at_ms), do: max(monotonic_ms() - started_at_ms, 0)

  @spec prompt_hash(String.t()) :: String.t()
  def prompt_hash(prompt) when is_binary(prompt), do: :crypto.hash(:sha256, prompt) |> Base.encode16(case: :lower)

  @spec stream_summary(term()) :: String.t()
  def stream_summary(payload), do: AppServerEventFields.stream_summary(payload)

  defp base_fields do
    %{
      component: "agent_provider.codebuddy_code",
      agent_provider_kind: @provider_kind
    }
  end
end
