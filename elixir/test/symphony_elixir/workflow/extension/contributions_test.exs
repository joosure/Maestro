defmodule SymphonyElixir.Workflow.Extension.ContributionsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extension
  alias SymphonyElixir.Workflow.Extension.Contributions
  alias SymphonyElixir.Workflow.Extension.ErrorCodes
  alias SymphonyElixir.Workflow.Extension.Runtime.Context, as: RuntimeContext
  alias SymphonyElixir.Workflow.Extension.Runtime.Result, as: RuntimeResult

  test "lists extension contributions through registered extensions" do
    assert {:ok, [__MODULE__.ProfileContribution]} =
             Contributions.list(:profiles, entries: [__MODULE__.ProfileExtension])

    assert [__MODULE__.ProfileContribution] =
             Contributions.list!(:profiles, entries: [__MODULE__.ProfileExtension])
  end

  test "fails closed when contribution callback returns a non-list" do
    assert {:error,
            %{
              code: code,
              reason: :contribution_not_list,
              callback: :profiles,
              value_type: "atom"
            }} = Contributions.list(:profiles, entries: [__MODULE__.InvalidProfileExtension])

    assert code == ErrorCodes.invalid_contribution()
  end

  test "fails closed when contribution callback raises without leaking message" do
    assert {:error,
            %{
              code: code,
              reason: :contribution_callback_failed,
              callback_error: %{kind: :error, exception: "RuntimeError"}
            } = error} = Contributions.list(:profiles, entries: [__MODULE__.RaisingProfileExtension])

    assert code == ErrorCodes.invalid_contribution()
    refute inspect(error) =~ "profile contribution unavailable"

    assert_raise ArgumentError, ~r/reason=contribution_callback_failed/, fn ->
      Contributions.list!(:profiles, entries: [__MODULE__.RaisingProfileExtension])
    end

    try do
      Contributions.list!(:profiles, entries: [__MODULE__.RaisingProfileExtension])
    rescue
      error in ArgumentError ->
        refute Exception.message(error) =~ "profile contribution unavailable"
    end
  end

  test "children fail closed on invalid returns" do
    assert {:error,
            %{
              code: code,
              reason: :children_not_list,
              callback: :children,
              value_type: "atom"
            }} = Contributions.children(entries: [__MODULE__.InvalidChildrenExtension])

    assert code == ErrorCodes.invalid_contribution()

    assert_raise ArgumentError, ~r/reason=children_not_list/, fn ->
      Contributions.children!(entries: [__MODULE__.InvalidChildrenExtension])
    end
  end

  test "options must be keyword lists" do
    assert {:error, %{code: code, reason: :opts_not_keyword, value_type: "list"}} =
             Contributions.list(:profiles, [{"entries", [__MODULE__.ProfileExtension]}])

    assert code == ErrorCodes.invalid_contribution()
  end

  defmodule ProfileContribution do
    @moduledoc false
  end

  defmodule ProfileExtension do
    @moduledoc false
    @behaviour Extension
    @behaviour Extension.ContributionCallbacks

    @impl true
    def id, do: "test.profile_contribution"

    @impl true
    def run_poll_cycle(%RuntimeContext{}, _opts), do: RuntimeResult.replace_extension_state(%{})

    @impl true
    def profiles, do: [ProfileContribution]
  end

  defmodule InvalidProfileExtension do
    @moduledoc false
    @behaviour Extension
    @behaviour Extension.ContributionCallbacks

    @impl true
    def id, do: "test.invalid_profile_contribution"

    @impl true
    def run_poll_cycle(%RuntimeContext{}, _opts), do: RuntimeResult.replace_extension_state(%{})

    @impl true
    def profiles, do: :not_a_list
  end

  defmodule RaisingProfileExtension do
    @moduledoc false
    @behaviour Extension
    @behaviour Extension.ContributionCallbacks

    @impl true
    def id, do: "test.raising_profile_contribution"

    @impl true
    def run_poll_cycle(%RuntimeContext{}, _opts), do: RuntimeResult.replace_extension_state(%{})

    @impl true
    def profiles, do: raise("profile contribution unavailable")
  end

  defmodule InvalidChildrenExtension do
    @moduledoc false
    @behaviour Extension
    @behaviour Extension.ContributionCallbacks

    @impl true
    def id, do: "test.invalid_children_contribution"

    @impl true
    def run_poll_cycle(%RuntimeContext{}, _opts), do: RuntimeResult.replace_extension_state(%{})

    @impl true
    def children(_opts), do: :not_a_list
  end
end
