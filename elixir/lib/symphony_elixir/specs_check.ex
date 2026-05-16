defmodule SymphonyElixir.SpecsCheck do
  @moduledoc false

  @type finding :: %{
          file: String.t(),
          module: String.t(),
          name: atom(),
          arity: non_neg_integer(),
          line: pos_integer()
        }

  @type boundary_violation :: %{
          file: String.t(),
          line: pos_integer(),
          target: String.t(),
          reason: atom(),
          message: String.t()
        }

  @spec missing_public_specs([Path.t()], keyword()) :: [finding()]
  def missing_public_specs(paths, opts \\ []) do
    exemptions =
      opts
      |> Keyword.get(:exemptions, [])
      |> MapSet.new()

    paths
    |> Enum.flat_map(&collect_elixir_files/1)
    |> Enum.flat_map(&file_findings(&1, exemptions))
    |> Enum.sort_by(&{&1.file, &1.line, &1.name, &1.arity})
  end

  @spec spec_corpus_boundary_violations(Path.t(), keyword()) :: [boundary_violation()]
  def spec_corpus_boundary_violations(root \\ File.cwd!(), opts \\ []) do
    repo_root = resolve_repo_root(root)
    specs_dir = Path.join(repo_root, "specs")

    if File.dir?(specs_dir) do
      repo_root
      |> collect_text_files(opts)
      |> Enum.flat_map(&boundary_violations_for_file(&1, repo_root, specs_dir))
      |> Enum.uniq_by(&{&1.file, &1.line, &1.target, &1.reason})
      |> Enum.sort_by(&{&1.file, &1.line, &1.target, &1.reason})
    else
      []
    end
  end

  @spec finding_identifier(finding()) :: String.t()
  def finding_identifier(%{module: module, name: name, arity: arity}) do
    "#{module}.#{name}/#{arity}"
  end

  @spec boundary_violation_message(boundary_violation()) :: String.t()
  def boundary_violation_message(%{file: file, line: line, message: message}) do
    "#{file}:#{line} #{message}"
  end

  defp collect_elixir_files(path) do
    cond do
      File.regular?(path) and String.ends_with?(path, ".ex") ->
        [path]

      File.dir?(path) ->
        Path.wildcard(Path.join(path, "**/*.ex"))

      true ->
        []
    end
  end

  defp collect_text_files(repo_root, opts) do
    excluded_dirs =
      opts
      |> Keyword.get(:excluded_dirs, default_boundary_excluded_dirs())
      |> MapSet.new()

    repo_root
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&(File.regular?(&1) and boundary_text_file?(&1)))
    |> Enum.reject(&boundary_excluded_path?(&1, repo_root, excluded_dirs))
    |> Enum.sort()
  end

  defp default_boundary_excluded_dirs do
    ~w[.git .elixir_ls _build deps node_modules priv/static]
  end

  defp boundary_text_file?(path) do
    Path.extname(path) in ~w[.ex .exs .heex .md .txt .sh .yml .yaml .json .toml]
  end

  defp boundary_excluded_path?(path, repo_root, excluded_dirs) do
    path
    |> Path.relative_to(repo_root)
    |> Path.split()
    |> Enum.any?(&MapSet.member?(excluded_dirs, &1))
  end

  defp boundary_violations_for_file(path, repo_root, specs_dir) do
    relative_path = Path.relative_to(path, repo_root)

    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      if inside_specs?(path, specs_dir) do
        specs_file_violations(path, relative_path, line, line_number, specs_dir)
      else
        outside_specs_file_violations(path, relative_path, line, line_number, specs_dir)
      end
    end)
  end

  defp specs_file_violations(path, relative_path, line, line_number, specs_dir) do
    markdown_targets = markdown_link_targets(line)
    markdown_target_set = MapSet.new(markdown_targets)

    markdown_violations =
      markdown_targets
      |> Enum.flat_map(fn target ->
        cond do
          skip_markdown_boundary_target?(target) ->
            []

          external_target?(target) ->
            [
              boundary_violation(
                relative_path,
                line_number,
                target,
                :spec_external_link,
                "spec corpus files must be self-contained and may not link to external URLs"
              )
            ]

          target_outside_specs?(path, target, specs_dir) ->
            [
              boundary_violation(
                relative_path,
                line_number,
                target,
                :spec_link_outside_corpus,
                "spec corpus files may only link to files inside specs/"
              )
            ]

          true ->
            []
        end
      end)

    raw_external_violations =
      line
      |> raw_external_targets()
      |> Enum.reject(&MapSet.member?(markdown_target_set, &1))
      |> Enum.map(fn target ->
        boundary_violation(
          relative_path,
          line_number,
          target,
          :spec_external_reference,
          "spec corpus files must be self-contained and may not reference external URLs"
        )
      end)

    markdown_violations ++ raw_external_violations
  end

  defp outside_specs_file_violations(path, relative_path, line, line_number, specs_dir) do
    markdown_targets = markdown_link_targets(line)
    markdown_target_set = MapSet.new(markdown_targets)

    markdown_violations =
      markdown_targets
      |> Enum.filter(&target_inside_specs?(path, &1, specs_dir))
      |> Enum.map(fn target ->
        boundary_violation(
          relative_path,
          line_number,
          target,
          :outside_link_to_spec_corpus,
          "files outside specs/ must not link to private spec corpus files"
        )
      end)

    raw_path_violations =
      line
      |> raw_specs_path_targets()
      |> Enum.reject(&MapSet.member?(markdown_target_set, &1))
      |> Enum.filter(&target_inside_specs?(path, &1, specs_dir))
      |> Enum.map(fn target ->
        boundary_violation(
          relative_path,
          line_number,
          target,
          :outside_reference_to_spec_corpus,
          "files outside specs/ must not reference private spec corpus files"
        )
      end)

    markdown_violations ++ raw_path_violations
  end

  defp markdown_link_targets(line) when is_binary(line) do
    ~r/\[[^\]]+\]\(([^)]+)\)/
    |> Regex.scan(line, capture: :all_but_first)
    |> Enum.map(fn [target] -> normalize_markdown_target(target) end)
  end

  defp raw_specs_path_targets(line) when is_binary(line) do
    ~r/(?:^|[\s'"`(])((?:(?:\.\.?\/)+)?specs\/[^\s'"`)]+\.md(?:#[^\s'"`)]+)?|\/[^\s'"`)]+\/specs\/[^\s'"`)]+\.md(?:#[^\s'"`)]+)?|file:\/\/[^\s'"`)]+\/specs\/[^\s'"`)]+\.md(?:#[^\s'"`)]+)?)/
    |> Regex.scan(line, capture: :all_but_first)
    |> Enum.map(fn [target] -> normalize_markdown_target(target) end)
  end

  defp raw_external_targets(line) when is_binary(line) do
    ~r/(?:https?:\/\/|mailto:|file:\/\/)[^\s'"`)]+/
    |> Regex.scan(line)
    |> Enum.map(fn [target] -> normalize_markdown_target(target) end)
  end

  defp normalize_markdown_target(target) do
    target
    |> String.trim()
    |> String.trim_leading("<")
    |> String.trim_trailing(">")
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
    |> String.split("#", parts: 2)
    |> List.first()
  end

  defp skip_markdown_boundary_target?(""), do: true
  defp skip_markdown_boundary_target?("#" <> _anchor), do: true
  defp skip_markdown_boundary_target?(_target), do: false

  defp external_target?(target) when is_binary(target) do
    String.starts_with?(target, ["http://", "https://", "mailto:", "file://"])
  end

  defp target_inside_specs?(_source_path, target, _specs_dir) when target in ["", nil], do: false

  defp target_inside_specs?(source_path, target, specs_dir) do
    case resolve_boundary_target(source_path, target, specs_dir) do
      {:ok, path} ->
        inside_specs?(path, specs_dir)

      :external ->
        false
    end
  end

  defp target_outside_specs?(source_path, target, specs_dir) do
    case resolve_boundary_target(source_path, target, specs_dir) do
      {:ok, path} ->
        not inside_specs?(path, specs_dir)

      :external ->
        false
    end
  end

  defp resolve_boundary_target(source_path, target, specs_dir) do
    case file_url_target_path(target) do
      nil ->
        cond do
          external_target?(target) ->
            :external

          repo_root_relative_specs_target?(target) ->
            {:ok, Path.expand(trim_current_dir_prefix(target), Path.dirname(specs_dir))}

          true ->
            {:ok, resolve_link_target(source_path, target)}
        end

      path ->
        {:ok, path}
    end
  end

  defp file_url_target_path(target) when is_binary(target) do
    case URI.parse(target) do
      %URI{scheme: "file", path: path} when is_binary(path) -> URI.decode(path)
      _ -> nil
    end
  end

  defp repo_root_relative_specs_target?(target) do
    String.starts_with?(target, ["specs/", "./specs/"])
  end

  defp trim_current_dir_prefix("./" <> target), do: target
  defp trim_current_dir_prefix(target), do: target

  defp resolve_link_target(source_path, target) do
    if Path.type(target) == :absolute do
      Path.expand(target)
    else
      Path.expand(target, Path.dirname(source_path))
    end
  end

  defp inside_specs?(path, specs_dir) do
    expanded_path = Path.expand(path)
    expanded_specs_dir = Path.expand(specs_dir)

    expanded_path == expanded_specs_dir or String.starts_with?(expanded_path, expanded_specs_dir <> "/")
  end

  defp boundary_violation(file, line, target, reason, message) do
    %{file: file, line: line, target: target, reason: reason, message: "#{message}: #{target}"}
  end

  defp resolve_repo_root(root) do
    expanded_root = Path.expand(root)

    cond do
      File.dir?(Path.join(expanded_root, "specs")) ->
        expanded_root

      Path.basename(expanded_root) == "elixir" and File.dir?(Path.expand("../specs", expanded_root)) ->
        Path.expand("..", expanded_root)

      true ->
        expanded_root
    end
  end

  defp file_findings(file, exemptions) do
    with {:ok, source} <- File.read(file),
         {:ok, ast} <- Code.string_to_quoted(source, columns: true, file: file) do
      ast
      |> module_nodes()
      |> Enum.flat_map(fn {module_name, body} ->
        find_missing_specs(body, module_name, file, exemptions)
      end)
    else
      {:error, {line, error, token}} ->
        Mix.raise("Unable to parse #{file}:#{line} #{error} #{inspect(token)}")

      {:error, reason} ->
        Mix.raise("Unable to read #{file}: #{inspect(reason)}")
    end
  end

  defp module_nodes(ast) do
    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, [module_ast, [do: body]]} = node, acc ->
          {node, [{Macro.to_string(module_ast), body} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(modules)
  end

  defp find_missing_specs(body, module_name, file, exemptions) do
    body
    |> normalize_block()
    |> Enum.reduce(initial_state(), fn form, state ->
      consume_form(form, state, module_name, file, exemptions)
    end)
    |> Map.fetch!(:findings)
  end

  defp initial_state do
    %{pending_specs: MapSet.new(), pending_impl: false, seen_defs: MapSet.new(), findings: []}
  end

  defp consume_form({:@, _, [{:spec, _, spec_nodes}]}, state, _module_name, _file, _exemptions) do
    ids =
      spec_nodes
      |> Enum.flat_map(&extract_spec_identifiers/1)
      |> MapSet.new()

    %{state | pending_specs: MapSet.union(state.pending_specs, ids)}
  end

  defp consume_form({:@, _, [{:impl, _, _}]}, state, _module_name, _file, _exemptions) do
    %{state | pending_impl: true}
  end

  defp consume_form({:@, _, _}, state, _module_name, _file, _exemptions), do: state

  defp consume_form({:def, _, [_head_ast]}, state, _module_name, _file, _exemptions) do
    state
  end

  defp consume_form({:def, meta, [head_ast, _]} = _form, state, module_name, file, exemptions) do
    {name, arity} = def_head_to_identifier(head_ast)

    id = {name, arity}

    if MapSet.member?(state.seen_defs, id) do
      %{state | pending_specs: MapSet.new(), pending_impl: false}
    else
      finding = %{
        file: file,
        module: module_name,
        name: name,
        arity: arity,
        line: Keyword.get(meta, :line, 1)
      }

      next_state = %{
        state
        | pending_specs: MapSet.new(),
          pending_impl: false,
          seen_defs: MapSet.put(state.seen_defs, id)
      }

      if compliant?(finding, state, exemptions) do
        next_state
      else
        %{next_state | findings: [finding | next_state.findings]}
      end
    end
  end

  defp consume_form({:defp, _, _}, state, _module_name, _file, _exemptions) do
    %{state | pending_specs: MapSet.new(), pending_impl: false}
  end

  defp consume_form(_form, state, _module_name, _file, _exemptions) do
    %{state | pending_specs: MapSet.new(), pending_impl: false}
  end

  defp compliant?(finding, state, exemptions) do
    id = {finding.name, finding.arity}

    MapSet.member?(state.pending_specs, id) or
      state.pending_impl or
      MapSet.member?(exemptions, finding_identifier(finding))
  end

  defp normalize_block({:__block__, _, forms}), do: forms
  defp normalize_block(form), do: [form]

  defp extract_spec_identifiers({:"::", _, [head, _return_type]}) do
    case spec_head_to_identifier(head) do
      nil -> []
      id -> [id]
    end
  end

  defp extract_spec_identifiers({:when, _, [{:"::", _, [head, _return_type]} | _guards]}) do
    case spec_head_to_identifier(head) do
      nil -> []
      id -> [id]
    end
  end

  defp extract_spec_identifiers(_), do: []

  defp spec_head_to_identifier({:when, _, [inner | _guards]}), do: spec_head_to_identifier(inner)
  defp spec_head_to_identifier({name, _, args}) when is_atom(name) and is_list(args), do: {name, length(args)}
  defp spec_head_to_identifier({name, _, nil}) when is_atom(name), do: {name, 0}
  defp spec_head_to_identifier(_), do: nil

  defp def_head_to_identifier({:when, _, [head | _guards]}), do: def_head_to_identifier(head)
  defp def_head_to_identifier({name, _, args}) when is_atom(name) and is_list(args), do: {name, length(args)}
  defp def_head_to_identifier({name, _, nil}) when is_atom(name), do: {name, 0}
end
