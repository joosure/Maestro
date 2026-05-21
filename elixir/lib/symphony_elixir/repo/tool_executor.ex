defmodule SymphonyElixir.Repo.ToolExecutor do
  @moduledoc """
  Executes repo-core typed workflow tools through the provider-neutral Repo facade.
  """

  @dialyzer {:nowarn_function, typed_error: 1}

  alias SymphonyElixir.Agent.DynamicTool.{MetadataContract, Serializer}
  alias SymphonyElixir.Repo
  alias SymphonyElixir.Repo.Context
  alias SymphonyElixir.Repo.Error
  alias SymphonyElixir.Repo.Status
  alias SymphonyElixir.Workflow.CapabilityNames

  @schema_version "1"
  @risk_flags ["external_process", "filesystem_write"]
  @read_risk_flags ["external_process", "filesystem_read"]
  @metadata_schema_version_key MetadataContract.schema_version()
  @metadata_side_effect_key MetadataContract.side_effect()
  @metadata_risk_flags_key MetadataContract.risk_flags()
  @metadata_workflow_capability_key MetadataContract.workflow_capability()
  @metadata_source_kind_key MetadataContract.source_kind()

  @checkout_tool "repo_checkout"
  @diff_tool "repo_diff"
  @commit_tool "repo_commit"
  @push_tool "repo_push"

  @checkout_capability CapabilityNames.repo_checkout()
  @diff_capability CapabilityNames.repo_diff()
  @commit_capability CapabilityNames.repo_commit()
  @push_capability CapabilityNames.repo_push()

  @spec tool_specs(map()) :: [map()]
  def tool_specs(repo) when is_map(repo) do
    [
      checkout_spec(repo),
      diff_spec(repo),
      commit_spec(repo),
      push_spec(repo)
    ]
  end

  def tool_specs(_repo), do: []

  @spec supported_tool_names(map()) :: [String.t()]
  def supported_tool_names(repo) when is_map(repo), do: Enum.map(tool_specs(repo), &Map.fetch!(&1, "name"))
  def supported_tool_names(_repo), do: []

  @spec execute(map(), String.t() | nil, term(), keyword()) :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def execute(repo, tool, arguments, opts)

  def execute(repo, @checkout_tool, arguments, opts) when is_map(repo) and is_list(opts),
    do: checkout(repo, arguments, opts)

  def execute(repo, @diff_tool, arguments, opts) when is_map(repo) and is_list(opts),
    do: diff(repo, arguments, opts)

  def execute(repo, @commit_tool, arguments, opts) when is_map(repo) and is_list(opts),
    do: commit(repo, arguments, opts)

  def execute(repo, @push_tool, arguments, opts) when is_map(repo) and is_list(opts),
    do: push(repo, arguments, opts)

  def execute(repo, _tool, _arguments, _opts) when is_map(repo), do: unsupported_tool(repo)
  def execute(_repo, _tool, _arguments, _opts), do: {:error, :repo_dynamic_tool_context_unavailable}

  defp checkout_spec(repo) do
    tool_spec(
      repo,
      @checkout_tool,
      @checkout_capability,
      "Create or switch to a workflow branch through the provider-neutral repo layer.",
      "write",
      @risk_flags,
      %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "identifier" => %{"type" => ["string", "null"], "description" => "Workflow issue identifier used to derive a working branch."},
          "branch" => %{"type" => ["string", "null"], "description" => "Explicit branch name to create or switch to."},
          "base" => %{"type" => ["string", "null"], "description" => "Base ref for branch creation."},
          "mode" => %{
            "type" => ["string", "null"],
            "enum" => ["create_or_switch", "create", "switch", nil],
            "description" => "Checkout mode. Defaults to create_or_switch."
          },
          "sync_base" => %{"type" => "boolean", "description" => "Fetch and merge the configured base branch before checkout."}
        }
      }
    )
  end

  defp diff_spec(repo) do
    tool_spec(
      repo,
      @diff_tool,
      @diff_capability,
      "Read repository diff and optional whitespace validation through the provider-neutral repo layer.",
      "read_only",
      @read_risk_flags,
      %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "args" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "Additional git diff arguments allowed by repo-core."},
          "check" => %{"type" => "boolean", "description" => "Also run diff whitespace validation."}
        }
      }
    )
  end

  defp commit_spec(repo) do
    tool_spec(
      repo,
      @commit_tool,
      @commit_capability,
      "Stage and commit repository changes through the provider-neutral repo layer.",
      "write",
      @risk_flags,
      %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["message"],
        "properties" => %{
          "message" => %{"type" => "string", "description" => "Commit message."},
          "mode" => %{
            "type" => ["string", "null"],
            "enum" => ["all", "staged", nil],
            "description" => "Commit mode. Defaults to all."
          }
        }
      }
    )
  end

  defp push_spec(repo) do
    tool_spec(
      repo,
      @push_tool,
      @push_capability,
      "Push the workflow branch and verify the published head through the provider-neutral repo layer.",
      "write",
      @risk_flags ++ ["external_network"],
      %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "branch" => %{"type" => ["string", "null"], "description" => "Branch to push. Defaults to current branch."},
          "set_upstream" => %{"type" => "boolean", "description" => "Set upstream tracking on push."},
          "force_with_lease" => %{"type" => "boolean", "description" => "Use force-with-lease when history was intentionally rewritten."},
          "verify" => %{"type" => "boolean", "description" => "Verify remote published head matches local HEAD. Defaults to true."}
        }
      }
    )
  end

  defp tool_spec(repo, name, capability, description, side_effect, risk_flags, input_schema) do
    %{
      "name" => name,
      "description" => description,
      "inputSchema" => input_schema,
      @metadata_schema_version_key => @schema_version,
      @metadata_side_effect_key => side_effect,
      @metadata_risk_flags_key => risk_flags,
      @metadata_workflow_capability_key => capability,
      @metadata_source_kind_key => "repo",
      "repoPath" => Context.path(repo)
    }
  end

  defp checkout(repo, arguments, opts) do
    with {:ok, args} <- checkout_args(arguments),
         {:ok, branch} <- checkout_branch(repo, args, opts),
         :ok <- maybe_sync_base(repo, args, opts),
         {:ok, action} <- checkout_branch_action(repo, branch, args, opts),
         {:ok, status} <- Repo.status(Context.path(repo), opts) do
      {:success,
       success_payload(%{
         "action" => action,
         "branch" => branch,
         "status" => status_payload(status)
       })}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp diff(repo, arguments, opts) do
    with {:ok, args} <- diff_args(arguments),
         {:ok, diff_output} <- Repo.diff(Context.path(repo), args.args, opts),
         {:ok, check_output} <- maybe_diff_check(repo, args, opts),
         {:ok, status} <- Repo.status(Context.path(repo), opts) do
      {:success,
       success_payload(%{
         "diff" => diff_output,
         "diffCheck" => check_output,
         "status" => status_payload(status)
       })}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp commit(repo, arguments, opts) do
    with {:ok, args} <- commit_args(arguments),
         {:ok, result} <- commit_action(repo, args, opts),
         {:ok, status} <- Repo.status(Context.path(repo), opts) do
      {:success,
       success_payload(
         %{
           "action" => if(result == :noop, do: "noop", else: "committed"),
           "headSha" => if(result == :noop, do: nil, else: result),
           "status" => status_payload(status)
         },
         Map.get(args, :warnings, [])
       )}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp push(repo, arguments, opts) do
    with {:ok, args} <- push_args(arguments),
         {:ok, branch} <- push_branch(repo, args, opts),
         {:ok, local_head} <- Repo.head_sha(Context.path(repo), opts),
         {:ok, output} <- Repo.push(Context.path(repo), Context.remote_name(repo), branch, push_opts(args, opts)),
         {:ok, published_head} <- maybe_published_head(repo, branch, args, opts),
         :ok <- verify_published_head(args, local_head, published_head) do
      {:success,
       success_payload(%{
         "branch" => branch,
         "remote" => Context.remote_name(repo),
         "headSha" => local_head,
         "publishedHeadSha" => published_head,
         "output" => output
       })}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp checkout_args(arguments) when is_map(arguments) do
    with {:ok, mode} <- enum(arguments, "mode", ["create_or_switch", "create", "switch"], "create_or_switch") do
      {:ok,
       %{
         identifier: nullable_string(arguments, "identifier"),
         branch: nullable_string(arguments, "branch"),
         base: nullable_string(arguments, "base"),
         mode: mode,
         sync_base: optional_boolean(arguments, "sync_base", false)
       }}
    end
  end

  defp checkout_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object for repo checkout."}}

  defp diff_args(arguments) when is_map(arguments) do
    with {:ok, args} <- optional_string_list(arguments, "args") do
      {:ok, %{args: args, check: optional_boolean(arguments, "check", false)}}
    end
  end

  defp diff_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object for repo diff."}}

  defp commit_args(arguments) when is_map(arguments) do
    with {:ok, message} <- required_string(arguments, "message"),
         {:ok, mode, warnings} <- commit_mode(arguments) do
      {:ok, %{message: message, mode: mode, warnings: warnings}}
    end
  end

  defp commit_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object for repo commit."}}

  defp commit_mode(arguments) do
    case nullable_string(arguments, "mode") do
      nil ->
        {:ok, "all", []}

      mode when mode in ["all", "staged"] ->
        {:ok, mode, []}

      mode when mode in ["stage_all", "stage-all", "all_staged", "all-staged"] ->
        {:ok, "all", ["Normalized repo_commit mode #{inspect(mode)} to canonical mode \"all\". Use only \"all\" or \"staged\" in future calls."]}

      mode ->
        {:error, {:invalid_arguments, "Unsupported mode #{inspect(mode)}. Use one of: all, staged."}}
    end
  end

  defp push_args(arguments) when is_map(arguments) do
    {:ok,
     %{
       branch: nullable_string(arguments, "branch"),
       set_upstream: optional_boolean(arguments, "set_upstream", false),
       force_with_lease: optional_boolean(arguments, "force_with_lease", false),
       verify: optional_boolean(arguments, "verify", true)
     }}
  end

  defp push_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object for repo push."}}

  defp checkout_branch(_repo, %{branch: branch}, _opts) when is_binary(branch), do: {:ok, branch}

  defp checkout_branch(repo, %{identifier: identifier}, opts) when is_binary(identifier) do
    repo
    |> Context.repo_opts(opts)
    |> then(&Repo.working_branch(identifier, &1))
  end

  defp checkout_branch(_repo, _args, _opts) do
    {:error, {:invalid_arguments, "Repo checkout requires either branch or identifier."}}
  end

  defp maybe_sync_base(repo, %{sync_base: true}, opts) do
    base = Context.base_branch(repo, opts)
    remote = Context.remote_name(repo)
    path = Context.path(repo)

    case Repo.sync_base(path, remote, base, opts) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_sync_base(_repo, _args, _opts), do: :ok

  defp checkout_branch_action(repo, branch, %{mode: "switch"}, opts) do
    with {:ok, ^branch} <- Repo.switch_branch(Context.path(repo), branch, opts) do
      {:ok, "switched"}
    end
  end

  defp checkout_branch_action(repo, branch, %{mode: "create"} = args, opts) do
    with {:ok, ^branch} <- Repo.create_branch(Context.path(repo), branch, checkout_base_ref(repo, args, opts), opts) do
      {:ok, "created"}
    end
  end

  defp checkout_branch_action(repo, branch, %{mode: "create_or_switch"} = args, opts) do
    case Repo.create_branch(Context.path(repo), branch, checkout_base_ref(repo, args, opts), opts) do
      {:ok, ^branch} ->
        {:ok, "created"}

      {:error, %Error{code: :branch_exists}} ->
        with {:ok, ^branch} <- Repo.switch_branch(Context.path(repo), branch, opts) do
          {:ok, "switched"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp checkout_base_ref(_repo, %{base: base}, _opts) when is_binary(base), do: base

  defp checkout_base_ref(repo, _args, opts) do
    remote = Context.remote_name(repo)
    base = Context.base_branch(repo, opts)

    "#{remote}/#{base}"
  end

  defp maybe_diff_check(repo, %{check: true, args: args}, opts), do: Repo.diff_check(Context.path(repo), args, opts)
  defp maybe_diff_check(_repo, _args, _opts), do: {:ok, nil}

  defp commit_action(repo, %{mode: "staged", message: message}, opts),
    do: Repo.commit_staged(Context.path(repo), message, opts)

  defp commit_action(repo, %{message: message}, opts), do: Repo.commit_all(Context.path(repo), message, opts)

  defp push_branch(_repo, %{branch: branch}, _opts) when is_binary(branch), do: {:ok, branch}
  defp push_branch(repo, _args, opts), do: Repo.current_branch(Context.path(repo), opts)

  defp push_opts(args, opts) do
    opts
    |> maybe_put(:set_upstream, args.set_upstream)
    |> maybe_put(:force_with_lease, args.force_with_lease)
  end

  defp maybe_published_head(repo, branch, %{verify: true}, opts) do
    Repo.published_head_sha(Context.path(repo), Context.remote_name(repo), branch, opts)
  end

  defp maybe_published_head(_repo, _branch, _args, _opts), do: {:ok, nil}

  defp verify_published_head(%{verify: true}, local_head, published_head) when local_head != published_head do
    {:error, {:published_head_mismatch, local_head, published_head}}
  end

  defp verify_published_head(_args, _local_head, _published_head), do: :ok

  defp status_payload(%Status{} = status) do
    %{
      "state" => Atom.to_string(status.state),
      "path" => status.path,
      "root" => status.root,
      "branch" => status.branch,
      "headSha" => status.head_sha,
      "clean" => status.clean?,
      "dirty" => status.dirty?,
      "conflicted" => status.conflicted?,
      "detached" => status.detached?,
      "missing" => status.missing?,
      "entries" => Serializer.json_safe_value(status.entries)
    }
  end

  defp success_payload(data, warnings \\ []) do
    %{"data" => Serializer.json_safe_value(data), "warnings" => Serializer.json_safe_value(warnings)}
  end

  defp typed_failure(reason) do
    {code, message, details} = typed_error(reason)
    {:failure, %{"error" => %{"code" => code, "message" => message, "details" => details}}}
  end

  defp typed_error({:invalid_arguments, message}), do: {"invalid_arguments", message, %{}}

  defp typed_error({:published_head_mismatch, local_head, published_head}) do
    {"conflict", "Published head does not match local HEAD.", %{"headSha" => local_head, "publishedHeadSha" => published_head}}
  end

  defp typed_error(%Error{} = error) do
    {
      error.code |> to_string(),
      error.message || "Repo typed workflow tool execution failed.",
      %{
        "operation" => error.operation && to_string(error.operation),
        "path" => error.path,
        "retryable" => error.retryable?,
        "details" => Serializer.json_safe_value(error.details)
      }
    }
  end

  defp typed_error(reason) do
    {"provider_request_failed", "Repo typed workflow tool execution failed.", %{"reason" => inspect(reason)}}
  end

  defp unsupported_tool(repo) do
    {:failure,
     %{
       "error" => %{
         "message" => "Unsupported repo dynamic tool.",
         "supportedTools" => supported_tool_names(repo)
       }
     }}
  end

  defp required_string(arguments, key) do
    case nullable_string(arguments, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:invalid_arguments, "Missing required string field #{key}."}}
    end
  end

  defp nullable_string(arguments, key) do
    arguments
    |> optional_value(key)
    |> case do
      nil -> nil
      value when is_binary(value) -> trim_string(value)
      value when is_integer(value) -> Integer.to_string(value)
      value when is_atom(value) -> value |> Atom.to_string() |> trim_string()
      _value -> nil
    end
  end

  defp enum(arguments, key, values, default) do
    case nullable_string(arguments, key) || default do
      value ->
        if value in values do
          {:ok, value}
        else
          {:error, {:invalid_arguments, "Unsupported #{key} #{inspect(value)}."}}
        end
    end
  end

  defp optional_boolean(arguments, key, default) do
    case optional_value(arguments, key) do
      value when is_boolean(value) -> value
      _value -> default
    end
  end

  defp optional_string_list(arguments, key) do
    case optional_value(arguments, key) do
      nil ->
        {:ok, []}

      values when is_list(values) ->
        {:ok,
         values
         |> Enum.flat_map(fn value ->
           case trim_string(value) do
             nil -> []
             normalized -> [normalized]
           end
         end)}

      _value ->
        {:error, {:invalid_arguments, "#{key} must be a list of strings."}}
    end
  end

  defp optional_value(arguments, key) do
    arguments
    |> fetch_optional_value(key)
    |> fallback_optional_value(arguments, camelize(key))
    |> fallback_optional_value(arguments, atom_key(key))
    |> case do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp fallback_optional_value({:ok, _value} = result, _arguments, _key), do: result
  defp fallback_optional_value(:error, arguments, key), do: fetch_optional_value(arguments, key)

  defp fetch_optional_value(_arguments, nil), do: :error
  defp fetch_optional_value(arguments, key), do: Map.fetch(arguments, key)

  defp trim_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim_string(_value), do: nil

  defp camelize(key) do
    [first | rest] = String.split(key, "_")
    Enum.join([first | Enum.map(rest, &String.capitalize/1)])
  end

  defp atom_key("identifier"), do: :identifier
  defp atom_key("branch"), do: :branch
  defp atom_key("base"), do: :base
  defp atom_key("mode"), do: :mode
  defp atom_key("sync_base"), do: :sync_base
  defp atom_key("args"), do: :args
  defp atom_key("check"), do: :check
  defp atom_key("message"), do: :message
  defp atom_key("set_upstream"), do: :set_upstream
  defp atom_key("force_with_lease"), do: :force_with_lease
  defp atom_key("verify"), do: :verify
  defp atom_key(_key), do: nil

  defp maybe_put(opts, _key, false), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
