defmodule SymphonyElixir.AgentProvider.TurnStatus do
  @moduledoc false

  @type status :: :completed | :failed | :cancelled | :input_required | :timeout | :blocked

  @completed "completed"
  @failed "failed"
  @cancelled "cancelled"
  @input_required "input_required"
  @timeout "timeout"
  @blocked "blocked"

  @status_by_atom %{
    completed: @completed,
    failed: @failed,
    cancelled: @cancelled,
    input_required: @input_required,
    timeout: @timeout,
    blocked: @blocked
  }

  @atom_by_status Map.new(@status_by_atom, fn {atom, status} -> {status, atom} end)
  @atoms [:completed, :failed, :cancelled, :input_required, :timeout, :blocked]
  @strings [@completed, @failed, @cancelled, @input_required, @timeout, @blocked]

  @spec completed() :: String.t()
  def completed, do: @completed

  @spec failed() :: String.t()
  def failed, do: @failed

  @spec cancelled() :: String.t()
  def cancelled, do: @cancelled

  @spec input_required() :: String.t()
  def input_required, do: @input_required

  @spec timeout() :: String.t()
  def timeout, do: @timeout

  @spec blocked() :: String.t()
  def blocked, do: @blocked

  @spec atoms() :: [status()]
  def atoms, do: @atoms

  @spec strings() :: [String.t()]
  def strings, do: @strings

  @spec string(term()) :: String.t()
  def string(nil), do: @completed
  def string(status) when is_atom(status), do: Map.get(@status_by_atom, status, Atom.to_string(status))
  def string(status) when is_binary(status), do: status
  def string(_status), do: @completed

  @spec normalize_atom(term(), keyword()) :: status()
  def normalize_atom(status, opts \\ [])

  def normalize_atom(nil, opts), do: Keyword.get(opts, :default, :completed)

  def normalize_atom(status, opts) when is_atom(status) do
    if status in @atoms do
      status
    else
      unknown_default(opts)
    end
  end

  def normalize_atom(status, _opts) when is_binary(status) and status in @strings, do: Map.fetch!(@atom_by_status, status)
  def normalize_atom(_status, opts), do: unknown_default(opts)

  defp unknown_default(opts), do: Keyword.get(opts, :unknown, Keyword.get(opts, :default, :completed))
end
