defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.KnownTarget.Registration.Options do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox

  @invalid_options_code "invalid_coding_pr_delivery_known_target_registration_options"
  @invalid_attrs_code "invalid_coding_pr_delivery_known_target_registration_attrs"
  @invalid_dependency_code "invalid_coding_pr_delivery_known_target_registration_dependency"

  @registration_only_opts [:registry, :inbox, :command_handler, :emit_event_fn]

  defstruct opts: [],
            registry: KnownTarget.Registry,
            inbox: Inbox,
            command_handler: nil,
            emit_event_fn: nil

  @type t :: %__MODULE__{
          opts: keyword(),
          registry: GenServer.server(),
          inbox: GenServer.server(),
          command_handler: (term() -> term()) | nil,
          emit_event_fn: (atom(), atom(), map() -> term()) | nil
        }

  @spec normalize(term()) :: {:ok, t()} | {:error, map()}
  def normalize(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      with {:ok, registry} <- server(opts, :registry, KnownTarget.Registry),
           {:ok, inbox} <- server(opts, :inbox, Inbox),
           {:ok, command_handler} <- optional_fun(opts, :command_handler, 1),
           {:ok, emit_event_fn} <- optional_fun(opts, :emit_event_fn, 3) do
        {:ok,
         %__MODULE__{
           opts: opts,
           registry: registry,
           inbox: inbox,
           command_handler: command_handler,
           emit_event_fn: emit_event_fn
         }}
      end
    else
      {:error, invalid_options(:options_not_keyword, opts)}
    end
  end

  def normalize(opts), do: {:error, invalid_options(:options_not_keyword, opts)}

  @spec registry_opts(t(), integer()) :: keyword()
  def registry_opts(%__MODULE__{} = options, now_ms) when is_integer(now_ms) do
    options.opts
    |> Keyword.drop(@registration_only_opts)
    |> Keyword.put(:server, options.registry)
    |> Keyword.put(:now_ms, now_ms)
  end

  @spec inbox_opts(t()) :: keyword()
  def inbox_opts(%__MODULE__{} = options), do: [server: options.inbox]

  @spec invalid_attrs(term()) :: map()
  def invalid_attrs(attrs), do: %{code: @invalid_attrs_code, value_type: Diagnostics.type_name(attrs)}

  @spec invalid_options(atom(), term()) :: map()
  def invalid_options(reason, value) when is_atom(reason) do
    %{
      code: @invalid_options_code,
      reason: reason,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec invalid_dependency(atom(), String.t(), term()) :: map()
  def invalid_dependency(option, expected, value) when is_atom(option) and is_binary(expected) do
    %{
      code: @invalid_dependency_code,
      reason: :invalid_dependency,
      option: option,
      expected: expected,
      value_type: Diagnostics.type_name(value)
    }
  end

  defp server(opts, key, default) when is_atom(key) do
    case Keyword.get(opts, key, default) do
      server when is_atom(server) or is_pid(server) or is_tuple(server) ->
        {:ok, server}

      server ->
        {:error, invalid_dependency(key, "GenServer server", server)}
    end
  end

  defp optional_fun(opts, key, arity) when is_atom(key) and is_integer(arity) do
    case Keyword.get(opts, key) do
      nil -> {:ok, nil}
      fun when is_function(fun, arity) -> {:ok, fun}
      fun -> {:error, invalid_dependency(key, "function/#{arity}", fun)}
    end
  end
end
