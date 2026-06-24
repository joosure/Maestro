defmodule SymphonyElixir.Agent.DynamicTool.SourceTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.DynamicTool.CompositeSource
  alias SymphonyElixir.Agent.DynamicTool.Source
  alias SymphonyElixir.Agent.DynamicTool.ToolSpec

  defmodule GoodSource do
    @behaviour SymphonyElixir.Agent.DynamicTool.Source

    def default_context(_opts), do: %{}
    def kind(_source_context), do: "  source_kind  "

    def tools(_source_context, _opts) do
      [
        %{
          "name" => "source_probe",
          "description" => "Probe source tool.",
          "inputSchema" => %{"type" => "object"},
          "capability" => "test.source_probe",
          "schemaVersion" => "1",
          "sideEffect" => "read_only"
        }
      ]
    end

    def environment(_source_context, _opts), do: %{"SOURCE_ENV" => "enabled"}
    def execute(_source_context, _tool, _arguments, _opts), do: {:success, %{}}
  end

  defmodule InvalidKindSource do
    @behaviour SymphonyElixir.Agent.DynamicTool.Source

    def default_context(_opts), do: %{}
    def kind(_source_context), do: :not_a_string
    def tools(_source_context, _opts), do: []
    def environment(_source_context, _opts), do: %{}
    def execute(_source_context, _tool, _arguments, _opts), do: {:success, %{}}
  end

  defmodule InvalidEnvironmentSource do
    @behaviour SymphonyElixir.Agent.DynamicTool.Source

    def default_context(_opts), do: %{}
    def kind(_source_context), do: "invalid_env"
    def tools(_source_context, _opts), do: []
    def environment(_source_context, _opts), do: %{SOURCE_ENV: :not_a_string}
    def execute(_source_context, _tool, _arguments, _opts), do: {:success, %{}}
  end

  defmodule InvalidToolsSource do
    @behaviour SymphonyElixir.Agent.DynamicTool.Source

    def default_context(_opts), do: %{}
    def kind(_source_context), do: "invalid_tools"
    def tools(_source_context, _opts), do: :not_a_list
    def environment(_source_context, _opts), do: %{}
    def execute(_source_context, _tool, _arguments, _opts), do: {:success, %{}}
  end

  defmodule InvalidToolSpecSource do
    @behaviour SymphonyElixir.Agent.DynamicTool.Source

    def default_context(_opts), do: %{}
    def kind(_source_context), do: "invalid_tool_spec"

    def tools(_source_context, _opts) do
      [
        %{
          "name" => "invalid tool name",
          "description" => "Invalid source tool.",
          "inputSchema" => %{"type" => "object"},
          "capability" => "test.invalid_tool",
          "schemaVersion" => "1",
          "sideEffect" => "read_only"
        }
      ]
    end

    def environment(_source_context, _opts), do: %{}
    def execute(_source_context, _tool, _arguments, _opts), do: {:success, %{}}
  end

  defmodule GoodCatalog do
    @behaviour SymphonyElixir.Agent.DynamicTool.SourceCatalog

    def source_specs(_opts), do: [GoodSource]
  end

  defmodule InvalidCatalogReturn do
    @behaviour SymphonyElixir.Agent.DynamicTool.SourceCatalog

    def source_specs(_opts), do: GoodSource
  end

  defmodule MissingCatalogBehaviour do
    def source_specs(_opts), do: [GoodSource]
  end

  test "tool_specs/3 returns normalized ToolSpec records" do
    assert [%ToolSpec{name: "source_probe", description: "Probe source tool."}] =
             Source.tool_specs(GoodSource, %{}, [])
  end

  test "source kind is normalized to non-empty string or nil" do
    assert Source.kind(GoodSource, %{}) == "source_kind"
  end

  test "invalid source kind fails closed" do
    assert_raise ArgumentError, ~r/invalid dynamic tool source kind/, fn ->
      Source.kind(InvalidKindSource, %{})
    end
  end

  test "source environment must be string-key string-value map" do
    assert Source.environment(GoodSource, %{}, []) == %{"SOURCE_ENV" => "enabled"}

    assert_raise ArgumentError, ~r/invalid dynamic tool source environment/, fn ->
      Source.environment(InvalidEnvironmentSource, %{}, [])
    end
  end

  test "source tools callback must return a list" do
    assert_raise ArgumentError, ~r/invalid dynamic tool source tools/, fn ->
      Source.tools(InvalidToolsSource, %{}, [])
    end
  end

  test "source-advertised invalid tool specs fail closed" do
    assert_raise ArgumentError, ~r/invalid dynamic tool source tool specs/, fn ->
      Source.tool_specs(InvalidToolSpecSource, %{}, [])
    end
  end

  test "dynamic_tool_sources opts must be a valid source spec list" do
    assert Source.from_opts(dynamic_tool_sources: [GoodSource]) == CompositeSource

    assert Source.from_opts(dynamic_tool_sources: [{GoodSource, %{session: "test"}}]) == CompositeSource

    assert_raise ArgumentError, ~r/invalid :dynamic_tool_sources/, fn ->
      Source.from_opts(dynamic_tool_sources: :not_a_list)
    end

    assert_raise ArgumentError, ~r/invalid dynamic tool source/, fn ->
      Source.from_opts(dynamic_tool_sources: [:not_loaded_source])
    end

    assert_raise ArgumentError, ~r/expected a source module or \{source, context\}/, fn ->
      Source.from_opts(dynamic_tool_sources: [%{"source" => GoodSource, "source_context" => %{session: "test"}}])
    end
  end

  test "dynamic_tool_sources opts can use catalog assembly" do
    assert Source.from_opts(dynamic_tool_sources: [catalogs: [GoodCatalog]]) == CompositeSource

    assert_raise ArgumentError, ~r/source_specs\/1 must return a list/, fn ->
      Source.from_opts(dynamic_tool_sources: [catalogs: [InvalidCatalogReturn]])
    end

    assert_raise ArgumentError, ~r/must implement SymphonyElixir.Agent.DynamicTool.SourceCatalog/, fn ->
      Source.from_opts(dynamic_tool_sources: [catalogs: [MissingCatalogBehaviour]])
    end
  end

  test "application dynamic_tool_sources config must use assembly shape" do
    Application.put_env(:symphony_elixir, :dynamic_tool_sources, catalogs: [GoodCatalog])

    assert Source.default() == CompositeSource

    Application.put_env(:symphony_elixir, :dynamic_tool_sources, [GoodSource])

    assert_raise ArgumentError, ~r/application configuration must use :catalogs or :sources/, fn ->
      Source.default()
    end
  end
end
