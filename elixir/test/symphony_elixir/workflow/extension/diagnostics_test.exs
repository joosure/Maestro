defmodule SymphonyElixir.Workflow.Extension.DiagnosticsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extension.Diagnostics

  test "type_name returns bounded string labels for runtime error diagnostics" do
    assert Diagnostics.type_name(true) == "boolean"
    assert Diagnostics.type_name(:ok) == "atom"
    assert Diagnostics.type_name("value") == "string"
    assert Diagnostics.type_name(1) == "integer"
    assert Diagnostics.type_name(1.0) == "float"
    assert Diagnostics.type_name([]) == "list"
    assert Diagnostics.type_name(%{}) == "map"
    assert Diagnostics.type_name(nil) == "nil"
    assert Diagnostics.type_name(self()) == "term"
  end

  test "type_atom returns compact registry labels without plugin payload semantics" do
    assert Diagnostics.type_atom([]) == :list
    assert Diagnostics.type_atom(%{}) == :map
    assert Diagnostics.type_atom(fn -> :ok end) == :function
    assert Diagnostics.type_atom("value") == :string
    assert Diagnostics.type_atom(:ok) == :atom
    assert Diagnostics.type_atom(nil) == :atom
    assert Diagnostics.type_atom(1) == :term
  end

  test "detailed_type_atom returns precise labels for runtime boundary diagnostics" do
    assert Diagnostics.detailed_type_atom(%RuntimeError{}) == :struct
    assert Diagnostics.detailed_type_atom(%{}) == :map
    assert Diagnostics.detailed_type_atom({:not, "json"}) == :tuple
    assert Diagnostics.detailed_type_atom(nil) == nil
    assert Diagnostics.detailed_type_atom(:ok) == :atom
    assert Diagnostics.detailed_type_atom(fn -> :ok end) == :function
    assert Diagnostics.detailed_type_atom(self()) == :pid
    assert Diagnostics.detailed_type_atom(make_ref()) == :reference
    assert Diagnostics.detailed_type_atom([]) == :list
    assert Diagnostics.detailed_type_atom("value") == :string
    assert Diagnostics.detailed_type_atom(1) == :integer
    assert Diagnostics.detailed_type_atom(1.0) == :float
  end

  test "exception and catch diagnostics do not expose messages or raw payloads" do
    error =
      try do
        raise "secret failure message"
      rescue
        error -> error
      end

    assert Diagnostics.exception(error) == %{kind: :error, exception: "RuntimeError"}
    refute inspect(Diagnostics.exception(error)) =~ "secret failure message"

    diagnostic = Diagnostics.caught(:throw, %{private: "secret"})
    assert diagnostic == %{kind: :throw, reason_type: "map"}
    refute inspect(diagnostic) =~ "secret"
  end
end
