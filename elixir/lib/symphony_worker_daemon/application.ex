defmodule SymphonyWorkerDaemon.Application do
  @moduledoc false

  use Application

  alias SymphonyWorkerDaemon.Application.Children

  @impl true
  @spec start(Application.start_type(), term()) :: Supervisor.on_start()
  def start(_type, args) do
    start_link(normalize_args(args))
  end

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    supervisor_name = Keyword.get(opts, :name, SymphonyWorkerDaemon.Supervisor)
    Supervisor.start_link(Children.build(opts), strategy: :rest_for_one, name: supervisor_name)
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  defp normalize_args(args) when is_list(args), do: args
  defp normalize_args(_args), do: []
end
