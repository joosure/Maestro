defmodule Mix.Tasks.Symphony.Workflow.Render do
  use Mix.Task

  alias SymphonyElixir.Workflow
  alias SymphonyElixir.Workflow.Templates

  @shortdoc "Render a bundled workflow template after partial expansion"

  @moduledoc """
  Renders a bundled workflow template alias after expanding `symphony-include`
  partials.

  By default the task prints the final expanded prompt body returned by
  `SymphonyElixir.Workflow.load/1`. Pass `--with-front-matter-source` to prepend
  the template's original front matter block without re-serializing it, so
  comments and ordering remain exactly as authored.

  Usage:

      mix symphony.workflow.render <template-alias>
      mix symphony.workflow.render --with-front-matter-source <template-alias>

  Examples:

      mix symphony.workflow.render <template-alias>
      mix symphony.workflow.render --with-front-matter-source <template-alias>.md
  """

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} =
      OptionParser.parse(args,
        strict: [with_front_matter_source: :boolean, help: :boolean],
        aliases: [h: :help]
      )

    cond do
      Keyword.get(opts, :help, false) ->
        Mix.shell().info(@moduledoc)

      invalid != [] ->
        Mix.raise("Unknown option for symphony.workflow.render: #{Enum.map_join(invalid, ", ", &elem(&1, 0))}")

      match?([_template_alias], positional) ->
        [template_alias] = positional
        render(template_alias, opts)

      true ->
        Mix.raise("Usage: mix symphony.workflow.render [--with-front-matter-source] <template-alias>")
    end
  end

  defp render(template_alias, opts) do
    with {:ok, path} <- Templates.resolve(template_alias),
         {:ok, %{prompt: prompt}} <- Workflow.load(path),
         {:ok, output} <- render_output(path, prompt, opts) do
      IO.write(output)
      IO.write("\n")
    else
      {:error, reason} when is_binary(reason) ->
        Mix.raise(reason)

      {:error, reason} ->
        Mix.raise("Failed to render workflow template #{inspect(template_alias)}: #{inspect(reason)}")
    end
  end

  defp render_output(path, prompt, opts) do
    if Keyword.get(opts, :with_front_matter_source, false) do
      with {:ok, source} <- File.read(path),
           {:ok, front_matter} <- source_front_matter(source) do
        {:ok, front_matter <> "\n" <> prompt}
      end
    else
      {:ok, prompt}
    end
  end

  defp source_front_matter(source) do
    case String.split(source, ~r/\R/, parts: 3) do
      ["---", rest] ->
        front_matter_from_tail(rest)

      ["---", tail, rest] ->
        front_matter_from_tail(tail <> "\n" <> rest)

      _other ->
        {:ok, ""}
    end
  end

  defp front_matter_from_tail(tail) do
    case :binary.match(tail, "\n---") do
      {index, _length} ->
        front_matter_body = binary_part(tail, 0, index)
        {:ok, "---\n" <> front_matter_body <> "\n---\n"}

      :nomatch ->
        {:error, :workflow_front_matter_end_not_found}
    end
  end
end
