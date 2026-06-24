defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Supervision.Options do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics

  @invalid_options_code "invalid_coding_pr_delivery_supervision_options"
  @missing_workflow_scope_code "missing_coding_pr_delivery_workflow_scope"

  @enforce_keys [:known_target_registry_opts, :watcher_opts]
  defstruct [:known_target_registry_opts, :watcher_opts]

  @type t :: %__MODULE__{
          known_target_registry_opts: keyword(),
          watcher_opts: keyword()
        }

  @type error :: %{
          required(:code) => String.t(),
          required(:message) => String.t(),
          required(:reason) => atom(),
          optional(:value_type) => atom()
        }

  @spec normalize(term()) :: {:ok, t()} | {:error, error()}
  def normalize(opts) when is_list(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, known_target_registry_opts} <- known_target_registry_opts(opts),
         {:ok, watcher_opts} <- watcher_opts(opts) do
      {:ok,
       %__MODULE__{
         known_target_registry_opts: known_target_registry_opts,
         watcher_opts: watcher_opts
       }}
    else
      false -> {:error, invalid_options(:options_not_keyword, opts)}
      {:error, reason} -> {:error, reason}
    end
  end

  def normalize(opts), do: {:error, invalid_options(:options_not_keyword, opts)}

  defp known_target_registry_opts(opts) do
    case Keyword.get(opts, :workflow_scope) do
      scope when is_map(scope) ->
        {:ok, [workflow_scope: scope]}

      _scope ->
        if Keyword.get(opts, :storage_backend) == false do
          {:ok, [storage_backend: false]}
        else
          {:error, missing_workflow_scope()}
        end
    end
  end

  defp watcher_opts(opts) do
    case Keyword.get(opts, :command_handler) do
      command_handler when is_function(command_handler, 1) ->
        {:ok, [command_handler: command_handler]}

      command_handler ->
        {:error, invalid_options(:command_handler_not_function, command_handler)}
    end
  end

  defp invalid_options(reason, value) do
    %{
      code: @invalid_options_code,
      message: "Coding PR Delivery supervision options are invalid.",
      reason: reason,
      value_type: Diagnostics.type_atom(value)
    }
  end

  defp missing_workflow_scope do
    %{
      code: @missing_workflow_scope_code,
      message: "Coding PR Delivery runtime children require an explicit workflow scope.",
      reason: :missing_workflow_scope
    }
  end
end
