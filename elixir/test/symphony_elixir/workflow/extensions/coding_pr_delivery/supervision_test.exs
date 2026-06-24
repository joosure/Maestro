defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.SupervisionTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.StartupBacklogBootstrap
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Supervision

  test "children returns extension runtime children with explicit workflow scope and command handler" do
    scope = %{"workflow" => "coding-pr-delivery"}
    command_handler = fn _command -> :ok end

    assert [
             Inbox,
             {KnownTarget.Registry, [workflow_scope: ^scope]},
             StartupBacklogBootstrap,
             {Watcher, watcher_opts}
           ] = Supervision.children(workflow_scope: scope, command_handler: command_handler)

    assert Keyword.fetch!(watcher_opts, :command_handler) == command_handler
  end

  test "children supports explicit memory-only known target registry storage" do
    command_handler = fn _command -> :ok end

    assert [
             Inbox,
             {KnownTarget.Registry, [storage_backend: false]},
             StartupBacklogBootstrap,
             {Watcher, watcher_opts}
           ] = Supervision.children(storage_backend: false, command_handler: command_handler)

    assert Keyword.fetch!(watcher_opts, :command_handler) == command_handler
  end

  test "children fails closed when workflow scope is missing" do
    assert [child_spec] = Supervision.children(command_handler: fn _command -> :ok end)

    assert {:error,
            %{
              code: "missing_coding_pr_delivery_workflow_scope",
              reason: :missing_workflow_scope
            }} = start_child(child_spec)
  end

  test "children fails closed when command handler is missing" do
    assert [child_spec] = Supervision.children(workflow_scope: %{"workflow" => "coding-pr-delivery"})

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_supervision_options",
              reason: :command_handler_not_function,
              value_type: :atom
            }} = start_child(child_spec)
  end

  test "children fails closed for non-keyword opts" do
    assert [child_spec] = CodingPrDelivery.children([:not_keyword])

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_supervision_options",
              reason: :options_not_keyword,
              value_type: :list
            }} = start_child(child_spec)
  end

  defp start_child(%{start: {module, function, args}}), do: apply(module, function, args)
end
