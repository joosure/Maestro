defmodule SymphonyElixir.RepoProvider.ChangeProposalBody do
  @moduledoc """
  Generates change-proposal bodies for repo-provider typed workflow tools.

  The typed tool keeps `body` optional so agents do not need to author or split
  provider Markdown during routine PR creation. This module owns the configured
  fallback body generation path and keeps provider adapters focused on provider
  API calls.
  """

  alias SymphonyElixir.RepoProvider.Config

  @type create_args :: %{
          optional(atom()) => term(),
          optional(:title) => String.t() | nil,
          optional(:base) => String.t() | nil,
          optional(:head) => String.t() | nil,
          optional(:labels) => [term()]
        }

  @type context :: %{
          repo: Config.t(),
          provider: String.t() | nil,
          repository: String.t() | nil
        }

  @callback generate(create_args(), context()) ::
              {:ok, String.t()} | {:error, term()} | String.t()

  @minimal_template """
  {{ title }}

  Created by Symphony typed workflow tool.

  Base: {{ base }}
  Head: {{ head }}
  """

  @template_placeholder ~r/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/
  @template_keys ~w(title base head labels provider repository)

  @minimal_generator_kind :minimal
  @static_generator_kind :static
  @template_generator_kind :template
  @module_generator_kind :module

  @generator_kind_by_name %{
    "minimal" => @minimal_generator_kind,
    "static" => @static_generator_kind,
    "template" => @template_generator_kind,
    "module" => @module_generator_kind
  }

  @spec generate(Config.t() | map(), create_args()) ::
          {:ok, String.t()} | {:error, {:invalid_arguments, String.t()}}
  def generate(repo, args) when is_map(args) do
    config = Config.new(repo)

    config
    |> Config.change_proposal_body_generator()
    |> render(args, context(config))
  end

  @spec validate_generator(term()) :: :ok | {:error, {:invalid_arguments, String.t()}}
  def validate_generator(nil), do: :ok
  def validate_generator(@minimal_generator_kind), do: :ok

  def validate_generator(generator) when is_binary(generator) do
    case normalize_generator_kind(generator) do
      nil -> :ok
      @minimal_generator_kind -> :ok
      {:unsupported, kind} -> {:error, invalid_generator("uses unsupported kind #{inspect(kind)}")}
      kind -> {:error, invalid_generator("uses unsupported kind #{inspect(generator_kind_label(kind))}")}
    end
  end

  def validate_generator(%{} = generator) do
    case generator_kind(generator) do
      nil -> {:error, invalid_generator("requires kind")}
      @minimal_generator_kind -> :ok
      @static_generator_kind -> validate_required_binary(generator, "body", generator_kind_label(@static_generator_kind))
      @template_generator_kind -> validate_template_generator(generator)
      @module_generator_kind -> validate_module_generator(generator)
      {:unsupported, kind} -> {:error, invalid_generator("uses unsupported kind #{inspect(kind)}")}
      kind -> {:error, invalid_generator("uses unsupported kind #{inspect(kind)}")}
    end
  end

  def validate_generator(module) when is_atom(module), do: validate_module(module)
  def validate_generator(generator), do: {:error, invalid_generator("must be minimal, a map, or a module atom; got #{inspect(generator)}")}

  defp render(nil, args, context), do: render(@minimal_generator_kind, args, context)

  defp render(generator, args, context) when is_binary(generator) do
    case normalize_generator_kind(generator) do
      nil -> render(@minimal_generator_kind, args, context)
      @minimal_generator_kind -> render(@minimal_generator_kind, args, context)
      {:unsupported, kind} -> {:error, invalid_generator("uses unsupported kind #{inspect(kind)}")}
      kind -> {:error, invalid_generator("uses unsupported kind #{inspect(kind)}")}
    end
  end

  defp render(@minimal_generator_kind, args, context), do: render_template(@minimal_template, args, context)

  defp render(%{} = generator, args, context) do
    case generator_kind(generator) do
      @minimal_generator_kind -> render(@minimal_generator_kind, args, context)
      @static_generator_kind -> generator |> map_value("body") |> generated_body()
      @template_generator_kind -> generator |> map_value("template") |> render_template(args, context)
      @module_generator_kind -> generator |> map_value("module") |> render_module(args, context)
      nil -> {:error, invalid_generator("requires kind")}
      {:unsupported, kind} -> {:error, invalid_generator("uses unsupported kind #{inspect(kind)}")}
      kind -> {:error, invalid_generator("uses unsupported kind #{inspect(kind)}")}
    end
  end

  defp render(module, args, context) when is_atom(module), do: render_module(module, args, context)
  defp render(generator, _args, _context), do: {:error, invalid_generator("must be minimal, a map, or a module atom; got #{inspect(generator)}")}

  defp render_template(template, args, context) when is_binary(template) do
    with :ok <- validate_template_placeholders(template) do
      @template_placeholder
      |> Regex.replace(template, fn _match, key -> template_value(key, args, context) end)
      |> generated_body()
    end
  end

  defp render_template(_template, _args, _context), do: {:error, invalid_generator("template generator requires a template string")}

  defp validate_template_generator(generator) do
    with :ok <- validate_required_binary(generator, "template", "template") do
      generator
      |> map_value("template")
      |> validate_template_placeholders()
    end
  end

  defp validate_template_placeholders(template) when is_binary(template) do
    unknown =
      @template_placeholder
      |> Regex.scan(template, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.reject(&(&1 in @template_keys))

    case unknown do
      [] -> :ok
      keys -> {:error, invalid_generator("template uses unsupported placeholder(s): #{Enum.join(keys, ", ")}")}
    end
  end

  defp validate_template_placeholders(_template), do: {:error, invalid_generator("template generator requires a template string")}

  defp render_module(module, args, context) when is_atom(module) do
    with :ok <- validate_module(module),
         result <- module.generate(args, context) do
      normalize_module_result(result)
    end
  end

  defp render_module(module, _args, _context) when is_binary(module),
    do: {:error, invalid_generator("module generator must be configured as a loaded module atom")}

  defp render_module(_module, _args, _context), do: {:error, invalid_generator("module generator requires a module atom")}

  defp validate_module_generator(generator) do
    generator
    |> map_value("module")
    |> validate_module_config()
  end

  defp validate_module_config(module) when is_atom(module), do: validate_module(module)

  defp validate_module_config(module) when is_binary(module),
    do: {:error, invalid_generator("module generator must be configured as a loaded module atom, not a string")}

  defp validate_module_config(_module), do: {:error, invalid_generator("module generator requires module")}

  defp validate_module(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :generate, 2) do
      :ok
    else
      {:error, invalid_generator("module #{inspect(module)} must export generate/2")}
    end
  end

  defp validate_required_binary(generator, key, kind) do
    case map_value(generator, key) do
      value when is_binary(value) ->
        if String.trim(value) != "" do
          :ok
        else
          {:error, invalid_generator("#{kind} generator requires #{key}")}
        end

      _value ->
        {:error, invalid_generator("#{kind} generator requires #{key}")}
    end
  end

  defp normalize_module_result({:ok, body}), do: generated_body(body)
  defp normalize_module_result({:error, reason}), do: {:error, reason}
  defp normalize_module_result(body) when is_binary(body), do: generated_body(body)
  defp normalize_module_result(_result), do: {:error, invalid_generator("module generator returned an unsupported value")}

  defp generated_body(body) when is_binary(body) do
    case String.trim(body) do
      "" -> {:error, invalid_generator("generated body is blank")}
      trimmed -> {:ok, trimmed}
    end
  end

  defp generated_body(_body), do: {:error, invalid_generator("generated body must be a string")}

  defp template_value("title", args, _context), do: string_value(args, :title)
  defp template_value("base", args, _context), do: string_value(args, :base)
  defp template_value("head", args, _context), do: string_value(args, :head)
  defp template_value("labels", args, _context), do: labels_value(Map.get(args, :labels, []))
  defp template_value("provider", _args, context), do: context.provider || ""
  defp template_value("repository", _args, context), do: context.repository || ""
  defp template_value(_key, _args, _context), do: ""

  defp labels_value(labels) when is_list(labels) do
    labels
    |> Enum.map(&to_label/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
  end

  defp labels_value(_labels), do: ""

  defp to_label(value) when is_binary(value), do: value
  defp to_label(value) when is_integer(value), do: Integer.to_string(value)
  defp to_label(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp to_label(_value), do: ""

  defp string_value(args, key) do
    case Map.get(args, key) do
      value when is_binary(value) -> value
      value when is_integer(value) -> Integer.to_string(value)
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      _value -> ""
    end
  end

  defp context(config) do
    %{
      repo: config,
      provider: Config.kind(config),
      repository: Config.repository(config)
    }
  end

  defp generator_kind(generator), do: generator |> map_value("kind") |> normalize_generator_kind()

  defp normalize_generator_kind(kind) do
    case normalize_kind_name(kind) do
      nil -> nil
      kind_name -> Map.get(@generator_kind_by_name, kind_name, {:unsupported, kind_name})
    end
  end

  defp normalize_kind_name(kind) when is_binary(kind) do
    case kind |> String.trim() |> String.downcase() do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_kind_name(kind) when is_atom(kind), do: kind |> Atom.to_string() |> normalize_kind_name()
  defp normalize_kind_name(_kind), do: nil

  defp generator_kind_label(kind) when is_atom(kind), do: Atom.to_string(kind)

  defp map_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp map_value(_map, _key), do: nil

  defp map_get_existing_atom(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp invalid_generator(message), do: {:invalid_arguments, "Invalid change proposal body generator: #{message}."}
end
