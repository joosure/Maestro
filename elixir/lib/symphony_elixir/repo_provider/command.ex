defmodule SymphonyElixir.RepoProvider.Command do
  @moduledoc false

  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.RepoProvider.Command.{Checks, Options}
  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Invocation
  alias SymphonyElixir.RepoProvider.Kinds
  alias SymphonyElixir.RepoProvider.LandWatch
  alias SymphonyElixir.RepoProvider.Result

  @spec run(Invocation.t(), map(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def run(invocation, repo_config, opts \\ [])

  def run(%Invocation{command: :current_kind}, repo_config, _opts) do
    {:ok,
     %Result{
       mode: :text,
       payload: RepoProvider.current_kind(repo_config)
     }}
  end

  def run(%Invocation{command: :auth_status}, repo_config, opts) do
    with {:ok, payload} <- RepoProvider.auth_status(repo_config, opts) do
      {:ok, %Result{mode: :text, payload: payload}}
    end
  end

  def run(%Invocation{command: :pr_view} = invocation, repo_config, opts) do
    with {:ok, payload} <- RepoProvider.pr_view(repo_config, Options.provider_opts(invocation, [:number], opts)) do
      {:ok,
       %Result{
         mode: :json,
         payload: payload,
         json_fields: invocation.json_fields,
         jq: invocation.jq,
         query_label: query_label(repo_config)
       }}
    end
  end

  def run(%Invocation{command: :pr_create} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_create(
             repo_config,
             Options.provider_opts(invocation, [:title, :body, :base, :head], opts)
           ) do
      {:ok, %Result{mode: :text, payload: payload}}
    end
  end

  def run(%Invocation{command: :pr_edit} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_edit(
             repo_config,
             Options.provider_opts(invocation, [:number, :title, :body, :base], opts)
           ) do
      {:ok, %Result{mode: :text, payload: payload}}
    end
  end

  def run(%Invocation{command: :pr_add_label} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_add_label(
             repo_config,
             Options.provider_opts(invocation, [:label, :number], opts)
           ) do
      {:ok, %Result{mode: :text, payload: payload}}
    end
  end

  def run(%Invocation{command: :pr_issue_comments} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_issue_comments(
             repo_config,
             Options.provider_opts(invocation, [:number], opts)
           ) do
      {:ok,
       %Result{
         mode: :json,
         payload: payload,
         json_fields: invocation.json_fields,
         jq: invocation.jq,
         query_label: query_label(repo_config)
       }}
    end
  end

  def run(%Invocation{command: :pr_add_issue_comment} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_add_issue_comment(
             repo_config,
             Options.provider_opts(invocation, [:body, :number], opts)
           ) do
      {:ok, %Result{mode: :json, payload: payload, query_label: query_label(repo_config)}}
    end
  end

  def run(%Invocation{command: :pr_reviews} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_reviews(
             repo_config,
             Options.provider_opts(invocation, [:number], opts)
           ) do
      {:ok,
       %Result{
         mode: :json,
         payload: payload,
         json_fields: invocation.json_fields,
         jq: invocation.jq,
         query_label: query_label(repo_config)
       }}
    end
  end

  def run(%Invocation{command: :pr_review_comments} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_review_comments(
             repo_config,
             Options.provider_opts(invocation, [:number], opts)
           ) do
      {:ok,
       %Result{
         mode: :json,
         payload: payload,
         json_fields: invocation.json_fields,
         jq: invocation.jq,
         query_label: query_label(repo_config)
       }}
    end
  end

  def run(%Invocation{command: :pr_reply_review_comment} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_reply_review_comment(
             repo_config,
             Options.provider_opts(invocation, [:comment_id, :body, :number], opts)
           ) do
      {:ok, %Result{mode: :json, payload: payload, query_label: query_label(repo_config)}}
    end
  end

  def run(%Invocation{command: :pr_close} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_close(
             repo_config,
             Options.provider_opts(invocation, [:number, :comment], opts)
           ) do
      {:ok, %Result{mode: :text, payload: payload}}
    end
  end

  def run(%Invocation{command: :pr_merge} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.pr_merge(
             repo_config,
             Options.provider_opts(invocation, [:number, :merge_style, :subject, :body], opts)
           ) do
      {:ok, %Result{mode: :text, payload: payload}}
    end
  end

  def run(%Invocation{command: :pr_land_watch} = invocation, repo_config, opts) do
    with {:ok, output, exit_code} <- LandWatch.watch(repo_config, Options.land_watch_opts(invocation, opts)) do
      {:ok, %Result{mode: :text, payload: output, exit_code: exit_code}}
    end
  end

  def run(%Invocation{command: :pr_checks} = invocation, repo_config, opts) do
    Checks.run(repo_config, invocation, opts, query_label(repo_config))
  end

  def run(%Invocation{command: :api} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.api(
             repo_config,
             Options.api_opts(invocation, opts)
           ) do
      {:ok,
       %Result{
         mode: :json,
         payload: payload,
         jq: invocation.jq,
         query_label: query_label(repo_config)
       }}
    end
  end

  def run(%Invocation{command: :run_list} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.run_list(
             repo_config,
             Options.provider_opts(invocation, [:branch, :limit], opts)
           ) do
      {:ok,
       %Result{
         mode: :json,
         payload: payload,
         json_fields: invocation.json_fields,
         jq: invocation.jq,
         query_label: query_label(repo_config)
       }}
    end
  end

  def run(%Invocation{command: :run_view, log?: true, json_fields: fields, jq: jq}, _repo_config, _opts)
      when is_list(fields) or is_binary(jq) do
    {:error, Error.invalid_invocation("repo-provider run-view --log does not support --json or --jq")}
  end

  def run(%Invocation{command: :run_view} = invocation, repo_config, opts) do
    with {:ok, payload} <-
           RepoProvider.run_view(
             repo_config,
             Options.provider_opts(invocation, [:run_id, :log?], opts)
           ) do
      if invocation.log? do
        {:ok, %Result{mode: :text, payload: payload}}
      else
        {:ok,
         %Result{
           mode: :json,
           payload: payload,
           json_fields: invocation.json_fields,
           jq: invocation.jq,
           query_label: query_label(repo_config)
         }}
      end
    end
  end

  defp query_label(repo_config) do
    repo_config
    |> RepoProvider.current_kind()
    |> Kinds.label()
  end
end
