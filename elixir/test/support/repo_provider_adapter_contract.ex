defmodule SymphonyElixir.RepoProviderAdapterContract do
  @moduledoc false

  defmacro __using__(opts) do
    adapter =
      opts
      |> Keyword.fetch!(:adapter)
      |> Macro.expand(__CALLER__)

    config_ast = Keyword.fetch!(opts, :config)
    callback_opts_ast = Keyword.get(opts, :callback_opts, quote(do: %{}))

    close_branch_ast =
      Keyword.get(opts, :close_branch, quote(do: "feature/repo-provider-contract"))

    capabilities = adapter.capabilities()
    capability_callbacks = SymphonyElixir.RepoProvider.Adapter.capability_callbacks()

    supported_config_options? = function_exported?(adapter, :supported_config_options, 0)
    auth_status? = :auth_status in capabilities
    pr_view? = :pr_view in capabilities
    pr_create? = :pr_create in capabilities
    pr_edit? = :pr_edit in capabilities
    pr_add_label? = :pr_add_label in capabilities
    pr_issue_comments? = :pr_issue_comments in capabilities
    pr_add_issue_comment? = :pr_add_issue_comment in capabilities
    pr_reviews? = :pr_reviews in capabilities
    pr_submit_review? = :pr_submit_review in capabilities
    pr_review_comments? = :pr_review_comments in capabilities
    pr_reply_review_comment? = :pr_reply_review_comment in capabilities
    pr_close? = :pr_close in capabilities
    pr_merge? = :pr_merge in capabilities
    pr_checks? = :pr_checks in capabilities
    api? = :api in capabilities
    run_list? = :run_list in capabilities
    run_view? = :run_view in capabilities
    close_open_pull_requests_for_branch? = :close_open_pull_requests_for_branch in capabilities
    healthcheck? = :healthcheck in capabilities

    # credo:disable-for-next-line Credo.Check.Refactor.LongQuoteBlocks
    quote do
      alias SymphonyElixir.RepoProvider.{Adapter, ConfigValidator}
      alias SymphonyElixir.RepoProvider.Error

      @adapter unquote(adapter)
      @capabilities unquote(capabilities)
      @capability_callbacks unquote(Macro.escape(capability_callbacks))

      defp adapter_contract_config, do: unquote(config_ast)
      defp adapter_contract_callback_opts, do: unquote(callback_opts_ast)
      defp adapter_contract_close_branch, do: unquote(close_branch_ast)

      test "kind/0 returns a non-empty string" do
        assert is_binary(@adapter.kind())
        refute @adapter.kind() == ""
      end

      test "defaults/0 returns a map" do
        assert is_map(@adapter.defaults())
      end

      test "capabilities/0 declares only known capabilities and matches implemented callbacks" do
        assert is_list(@adapter.capabilities())
        assert Enum.all?(@adapter.capabilities(), &is_atom/1)
        assert @adapter.capabilities() == @capabilities
        assert @capabilities == Enum.uniq(@capabilities)
        assert @capabilities == Enum.filter(Adapter.all_capabilities(), &(&1 in @capabilities))

        Enum.each(@capability_callbacks, fn {capability, arity} ->
          assert function_exported?(@adapter, capability, arity) == capability in @capabilities
        end)
      end

      test "validate_config/1 returns :ok or {:error, %RepoProvider.Error{}}" do
        assert adapter_contract_validate_result?(@adapter.validate_config(adapter_contract_config()))
      end

      if unquote(supported_config_options?) do
        test "supported_config_options/0 declares only known shared options" do
          supported = @adapter.supported_config_options()

          assert is_list(supported)
          assert Enum.all?(supported, &is_atom/1)
          assert supported == ConfigValidator.supported_config_options(@adapter)
        end

        test "shared required_pr_label option contract stays consistent" do
          config = adapter_contract_with_required_pr_label(adapter_contract_config())

          if :required_pr_label in @adapter.supported_config_options() do
            assert :ok == @adapter.validate_config(config)
          else
            assert {:error,
                    %Error{
                      code: :unsupported_option,
                      provider: provider,
                      operation: :validate_config
                    }} = @adapter.validate_config(config)

            assert provider == @adapter.kind()
          end
        end
      end

      if unquote(auth_status?) do
        test "auth_status/2 returns {:ok, binary} or {:error, _}" do
          assert adapter_contract_binary_result?(
                   @adapter.auth_status(
                     adapter_contract_config(),
                     adapter_contract_opts(:auth_status)
                   )
                 )
        end
      end

      if unquote(pr_view?) do
        test "pr_view/2 returns {:ok, map} or {:error, _}" do
          assert adapter_contract_map_result?(@adapter.pr_view(adapter_contract_config(), adapter_contract_opts(:pr_view)))
        end
      end

      if unquote(pr_create?) do
        test "pr_create/2 returns {:ok, binary} or {:error, _}" do
          assert adapter_contract_binary_result?(
                   @adapter.pr_create(
                     adapter_contract_config(),
                     adapter_contract_opts(:pr_create)
                   )
                 )
        end
      end

      if unquote(pr_edit?) do
        test "pr_edit/2 returns {:ok, binary} or {:error, _}" do
          assert adapter_contract_binary_result?(@adapter.pr_edit(adapter_contract_config(), adapter_contract_opts(:pr_edit)))
        end
      end

      if unquote(pr_add_label?) do
        test "pr_add_label/2 returns {:ok, binary} or {:error, _}" do
          assert adapter_contract_binary_result?(
                   @adapter.pr_add_label(
                     adapter_contract_config(),
                     adapter_contract_opts(:pr_add_label)
                   )
                 )
        end
      end

      if unquote(pr_issue_comments?) do
        test "pr_issue_comments/2 returns {:ok, list} or {:error, _}" do
          assert adapter_contract_list_result?(
                   @adapter.pr_issue_comments(
                     adapter_contract_config(),
                     adapter_contract_opts(:pr_issue_comments)
                   )
                 )
        end
      end

      if unquote(pr_add_issue_comment?) do
        test "pr_add_issue_comment/2 returns {:ok, map} or {:error, _}" do
          assert adapter_contract_map_result?(
                   @adapter.pr_add_issue_comment(
                     adapter_contract_config(),
                     adapter_contract_opts(:pr_add_issue_comment)
                   )
                 )
        end
      end

      if unquote(pr_reviews?) do
        test "pr_reviews/2 returns {:ok, list} or {:error, _}" do
          assert adapter_contract_list_result?(
                   @adapter.pr_reviews(
                     adapter_contract_config(),
                     adapter_contract_opts(:pr_reviews)
                   )
                 )
        end
      end

      if unquote(pr_submit_review?) do
        test "pr_submit_review/2 returns {:ok, map} or {:error, _}" do
          assert adapter_contract_map_result?(
                   @adapter.pr_submit_review(
                     adapter_contract_config(),
                     adapter_contract_opts(:pr_submit_review)
                   )
                 )
        end
      end

      if unquote(pr_review_comments?) do
        test "pr_review_comments/2 returns {:ok, list} or {:error, _}" do
          assert adapter_contract_list_result?(
                   @adapter.pr_review_comments(
                     adapter_contract_config(),
                     adapter_contract_opts(:pr_review_comments)
                   )
                 )
        end
      end

      if unquote(pr_reply_review_comment?) do
        test "pr_reply_review_comment/2 returns {:ok, map} or {:error, _}" do
          assert adapter_contract_map_result?(
                   @adapter.pr_reply_review_comment(
                     adapter_contract_config(),
                     adapter_contract_opts(:pr_reply_review_comment)
                   )
                 )
        end
      end

      if unquote(pr_close?) do
        test "pr_close/2 returns {:ok, binary} or {:error, _}" do
          assert adapter_contract_binary_result?(@adapter.pr_close(adapter_contract_config(), adapter_contract_opts(:pr_close)))
        end
      end

      if unquote(pr_merge?) do
        test "pr_merge/2 returns {:ok, binary} or {:error, _}" do
          assert adapter_contract_binary_result?(@adapter.pr_merge(adapter_contract_config(), adapter_contract_opts(:pr_merge)))
        end
      end

      if unquote(pr_checks?) do
        test "pr_checks/2 returns {:ok, list} or {:error, _}" do
          assert adapter_contract_list_result?(
                   @adapter.pr_checks(
                     adapter_contract_config(),
                     adapter_contract_opts(:pr_checks)
                   )
                 )
        end
      end

      if unquote(api?) do
        test "api/2 returns {:ok, _} or {:error, _}" do
          assert adapter_contract_any_result?(@adapter.api(adapter_contract_config(), adapter_contract_opts(:api)))
        end
      end

      if unquote(run_list?) do
        test "run_list/2 returns {:ok, list} or {:error, _}" do
          assert adapter_contract_list_result?(@adapter.run_list(adapter_contract_config(), adapter_contract_opts(:run_list)))
        end
      end

      if unquote(run_view?) do
        test "run_view/2 returns {:ok, map | binary} or {:error, _}" do
          assert adapter_contract_run_view_result?(@adapter.run_view(adapter_contract_config(), adapter_contract_opts(:run_view)))
        end
      end

      if unquote(close_open_pull_requests_for_branch?) do
        test "close_open_pull_requests_for_branch/3 returns :ok or {:error, _}" do
          assert adapter_contract_write_result?(
                   @adapter.close_open_pull_requests_for_branch(
                     adapter_contract_config(),
                     adapter_contract_close_branch(),
                     adapter_contract_opts(:close_open_pull_requests_for_branch)
                   )
                 )
        end
      end

      if unquote(healthcheck?) do
        test "healthcheck/2 returns :ok or {:error, _}" do
          assert adapter_contract_write_result?(
                   @adapter.healthcheck(
                     adapter_contract_config(),
                     adapter_contract_opts(:healthcheck)
                   )
                 )
        end
      end

      defp adapter_contract_opts(callback) when is_atom(callback) do
        case adapter_contract_callback_opts() do
          opts when is_map(opts) -> Map.get(opts, callback, [])
          opts when is_list(opts) -> Keyword.get(opts, callback, [])
          _other -> []
        end
      end

      defp adapter_contract_with_required_pr_label(config) when is_map(config) do
        provider =
          config
          |> Map.get(:provider, %{})
          |> Map.put(:kind, @adapter.kind())

        options =
          provider
          |> Map.get(:options, %{})
          |> Map.put(:required_pr_label, "release-ready")

        config
        |> Map.put(:provider, Map.put(provider, :options, options))
      end

      defp adapter_contract_validate_result?(result) do
        result == :ok or match?({:error, %Error{operation: :validate_config}}, result)
      end

      defp adapter_contract_binary_result?(result) do
        match?({:ok, value} when is_binary(value), result) or match?({:error, _reason}, result)
      end

      defp adapter_contract_map_result?(result) do
        match?({:ok, value} when is_map(value), result) or match?({:error, _reason}, result)
      end

      defp adapter_contract_list_result?(result) do
        match?({:ok, value} when is_list(value), result) or match?({:error, _reason}, result)
      end

      defp adapter_contract_run_view_result?(result) do
        match?({:ok, value} when is_map(value), result) or
          match?({:ok, value} when is_binary(value), result) or
          match?({:error, _reason}, result)
      end

      defp adapter_contract_any_result?(result) do
        match?({:ok, _value}, result) or match?({:error, _reason}, result)
      end

      defp adapter_contract_write_result?(result) do
        result == :ok or match?({:error, _reason}, result)
      end
    end
  end
end
