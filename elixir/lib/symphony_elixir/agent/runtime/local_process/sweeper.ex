defmodule SymphonyElixir.Agent.Runtime.LocalProcess.Sweeper do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.LocalProcess.Ledger
  alias SymphonyElixir.Platform.Process, as: PlatformProcess

  @default_grace_ms 500
  @default_kill_wait_ms 500
  @default_poll_ms 25

  @type sweep_result :: %{
          records: non_neg_integer(),
          terminated: non_neg_integer(),
          already_exited: non_neg_integer(),
          skipped: non_neg_integer(),
          failed: non_neg_integer()
        }

  @spec sweep(keyword()) :: sweep_result()
  def sweep(opts \\ []) when is_list(opts) do
    root = Ledger.root(opts)
    process_module = Keyword.get(opts, :process_module, PlatformProcess)

    root
    |> Ledger.list_records()
    |> Enum.reduce(empty_result(), fn record, acc ->
      record
      |> sweep_record(root, process_module, opts)
      |> accumulate(acc)
    end)
  end

  defp sweep_record(record, root, process_module, opts) do
    case positive_integer(record["os_pid"]) do
      {:ok, os_pid} ->
        cond do
          owner_alive?(record, process_module) ->
            :skipped

          not process_alive?(process_module, os_pid) ->
            Ledger.delete_record(root, record["id"])
            :already_exited

          not command_matches?(process_module, os_pid, record) ->
            :skipped

          true ->
            terminate_record_process(record, root, process_module, os_pid, opts)
        end

      :error ->
        Ledger.delete_record(root, record["id"])
        :skipped
    end
  end

  defp terminate_record_process(record, root, process_module, os_pid, opts) do
    termination =
      process_module.terminate_os_process_tree(os_pid,
        process_group?: Keyword.get(opts, :process_group?, true),
        grace_ms: Keyword.get(opts, :grace_ms, @default_grace_ms),
        kill_wait_ms: Keyword.get(opts, :kill_wait_ms, @default_kill_wait_ms),
        poll_ms: Keyword.get(opts, :poll_ms, @default_poll_ms)
      )

    if Map.get(termination, :alive?) do
      :failed
    else
      Ledger.delete_record(root, record["id"])
      :terminated
    end
  end

  defp owner_alive?(record, process_module) do
    case positive_integer(record["owner_os_pid"]) do
      {:ok, owner_os_pid} -> process_alive?(process_module, owner_os_pid)
      :error -> false
    end
  end

  defp command_matches?(process_module, os_pid, record) do
    tokens = record |> Map.get("command_match_tokens") |> List.wrap() |> Enum.filter(&valid_token?/1)

    cond do
      tokens == [] ->
        true

      not module_exports?(process_module, :os_process_command, 1) ->
        true

      true ->
        case process_module.os_process_command(os_pid) do
          {:ok, command_line} when is_binary(command_line) ->
            Enum.all?(tokens, &String.contains?(command_line, &1))

          _other ->
            false
        end
    end
  end

  defp process_alive?(process_module, os_pid) do
    module_exports?(process_module, :os_process_alive?, 1) and process_module.os_process_alive?(os_pid)
  end

  defp module_exports?(module, function, arity) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, function, arity)
  end

  defp valid_token?(value) when is_binary(value), do: String.trim(value) != ""
  defp valid_token?(_value), do: false

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _other -> :error
    end
  end

  defp positive_integer(_value), do: :error

  defp empty_result do
    %{records: 0, terminated: 0, already_exited: 0, skipped: 0, failed: 0}
  end

  defp accumulate(status, result) do
    result
    |> Map.update!(:records, &(&1 + 1))
    |> Map.update!(status_key(status), &(&1 + 1))
  end

  defp status_key(:terminated), do: :terminated
  defp status_key(:already_exited), do: :already_exited
  defp status_key(:failed), do: :failed
  defp status_key(_status), do: :skipped
end
