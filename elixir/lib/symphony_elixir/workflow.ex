defmodule SymphonyElixir.Workflow do
  @moduledoc """
  Loads workflow configuration and prompt from WORKFLOW.md.
  """

  alias SymphonyElixir.Workflow.Runtime.Store, as: WorkflowStore
  alias SymphonyElixir.Workflow.Templates

  @workflow_file_name "WORKFLOW.md"
  @partial_include_pattern ~r/^\s*<!--\s*symphony-include:\s*([^>]+?)\s*-->\s*$/
  @max_partial_depth 8

  @spec workflow_file_path() :: Path.t()
  def workflow_file_path do
    Application.get_env(:symphony_elixir, :workflow_file_path) ||
      Path.join(File.cwd!(), @workflow_file_name)
  end

  @spec set_workflow_file_path(Path.t()) :: :ok
  def set_workflow_file_path(path) when is_binary(path) do
    Application.put_env(:symphony_elixir, :workflow_file_path, path)
    maybe_reload_store()
    :ok
  end

  @spec clear_workflow_file_path() :: :ok
  def clear_workflow_file_path do
    Application.delete_env(:symphony_elixir, :workflow_file_path)
    maybe_reload_store()
    :ok
  end

  @type loaded_workflow :: %{
          config: map(),
          prompt: String.t(),
          prompt_template: String.t()
        }

  @spec current() :: {:ok, loaded_workflow()} | {:error, term()}
  def current do
    case Process.whereis(WorkflowStore) do
      pid when is_pid(pid) ->
        WorkflowStore.current()

      _ ->
        load()
    end
  end

  @spec load() :: {:ok, loaded_workflow()} | {:error, term()}
  def load do
    load(workflow_file_path())
  end

  @spec load(Path.t()) :: {:ok, loaded_workflow()} | {:error, term()}
  def load(path) when is_binary(path) do
    case File.read(path) do
      {:ok, content} ->
        parse(content, path)

      {:error, reason} ->
        {:error, {:missing_workflow_file, path, reason}}
    end
  end

  defp parse(content, path) do
    {front_matter_lines, prompt_lines} = split_front_matter(content)

    case front_matter_yaml_to_map(front_matter_lines) do
      {:ok, front_matter} ->
        case prompt_lines |> Enum.join("\n") |> expand_prompt_partials(path) do
          {:ok, prompt} ->
            prompt = String.trim(prompt)

            {:ok,
             %{
               config: front_matter,
               prompt: prompt,
               prompt_template: prompt
             }}

          {:error, reason} ->
            {:error, {:workflow_parse_error, reason}}
        end

      {:error, :workflow_front_matter_not_a_map} ->
        {:error, :workflow_front_matter_not_a_map}

      {:error, reason} ->
        {:error, {:workflow_parse_error, reason}}
    end
  end

  defp expand_prompt_partials(prompt, workflow_path) when is_binary(prompt) do
    expand_prompt_partials(prompt, workflow_path, 0)
  end

  defp expand_prompt_partials(_prompt, _workflow_path, depth) when depth > @max_partial_depth do
    {:error, {:workflow_partial_include_too_deep, @max_partial_depth}}
  end

  defp expand_prompt_partials(prompt, workflow_path, depth) do
    prompt
    |> String.split("\n", trim: false)
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
      case Regex.run(@partial_include_pattern, line, capture: :all_but_first) do
        [partial_ref] ->
          with {:ok, partial_path} <- resolve_partial_path(partial_ref, workflow_path),
               {:ok, partial} <- read_partial(partial_path),
               {:ok, expanded} <- expand_prompt_partials(partial, partial_path, depth + 1) do
            {:cont, {:ok, [expanded | acc]}}
          else
            {:error, reason} -> {:halt, {:error, reason}}
          end

        _no_include ->
          {:cont, {:ok, [line | acc]}}
      end
    end)
    |> case do
      {:ok, lines} -> {:ok, lines |> Enum.reverse() |> Enum.join("\n")}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_partial_path(partial_ref, workflow_path) do
    partial_ref = String.trim(partial_ref)

    cond do
      partial_ref == "" ->
        {:error, :workflow_partial_include_blank}

      Path.type(partial_ref) == :absolute ->
        {:error, {:workflow_partial_include_invalid, partial_ref}}

      partial_ref |> Path.split() |> Enum.any?(&(&1 in [".", ".."])) ->
        {:error, {:workflow_partial_include_invalid, partial_ref}}

      Path.extname(partial_ref) != ".md" ->
        {:error, {:workflow_partial_include_invalid, partial_ref}}

      String.starts_with?(partial_ref, "_partials/") ->
        {:ok, Templates.root() |> Path.join(partial_ref) |> Path.expand()}

      true ->
        {:ok, workflow_path |> Path.dirname() |> Path.join(partial_ref) |> Path.expand()}
    end
  end

  defp read_partial(partial_path) do
    with :ok <- ensure_partial_path_allowed(partial_path),
         {:ok, partial} <- File.read(partial_path) do
      {:ok, partial}
    else
      {:error, reason} when is_atom(reason) ->
        {:error, {:workflow_partial_include_read_failed, partial_path, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_partial_path_allowed(partial_path) do
    partials_root = Templates.root() |> Path.join("_partials") |> Path.expand()

    if String.starts_with?(partial_path, partials_root <> "/") do
      :ok
    else
      {:error, {:workflow_partial_include_outside_partials, partial_path}}
    end
  end

  defp split_front_matter(content) do
    lines = String.split(content, ~r/\R/, trim: false)

    case lines do
      ["---" | tail] ->
        {front, rest} = Enum.split_while(tail, &(&1 != "---"))

        case rest do
          ["---" | prompt_lines] -> {front, prompt_lines}
          _ -> {front, []}
        end

      _ ->
        {[], lines}
    end
  end

  defp front_matter_yaml_to_map(lines) do
    yaml = Enum.join(lines, "\n")

    if String.trim(yaml) == "" do
      {:ok, %{}}
    else
      case YamlElixir.read_from_string(yaml) do
        {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
        {:ok, _} -> {:error, :workflow_front_matter_not_a_map}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp maybe_reload_store do
    if Process.whereis(WorkflowStore) do
      try do
        _ = WorkflowStore.force_reload()
      catch
        :exit, _reason -> :ok
      end
    end

    :ok
  end
end
