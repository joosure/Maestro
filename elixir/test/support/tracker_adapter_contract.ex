defmodule SymphonyElixir.TrackerAdapterContract do
  @moduledoc false

  defmacro __using__(opts) do
    adapter =
      opts
      |> Keyword.fetch!(:adapter)
      |> Macro.expand(__CALLER__)

    config =
      opts
      |> Keyword.fetch!(:config)
      |> Code.eval_quoted([], __CALLER__)
      |> elem(0)

    dynamic_tools? = function_exported?(adapter, :dynamic_tools, 1)
    execute_dynamic_tool? = function_exported?(adapter, :execute_dynamic_tool, 4)
    project_ref? = function_exported?(adapter, :project_ref, 1)
    fetch_candidate_issues? = function_exported?(adapter, :fetch_candidate_issues, 2)
    fetch_issues_by_states? = function_exported?(adapter, :fetch_issues_by_states, 3)
    fetch_issue_states_by_ids? = function_exported?(adapter, :fetch_issue_states_by_ids, 3)
    create_comment? = function_exported?(adapter, :create_comment, 4)
    update_issue_state? = function_exported?(adapter, :update_issue_state, 4)
    prepare_workspace? = function_exported?(adapter, :prepare_workspace, 3)
    healthcheck? = function_exported?(adapter, :healthcheck, 2)

    quote do
      alias SymphonyElixir.Agent.DynamicTool.Spec
      alias SymphonyElixir.Tracker.ProjectRef

      @adapter unquote(adapter)
      @config unquote(Macro.escape(config))

      test "kind/0 returns a non-empty string" do
        assert is_binary(@adapter.kind())
        refute @adapter.kind() == ""
      end

      test "defaults/0 returns a map" do
        assert is_map(@adapter.defaults())
      end

      test "validate_config/1 returns :ok or {:error, _}" do
        assert adapter_contract_write_result?(@adapter.validate_config(@config))
      end

      if unquote(dynamic_tools?) do
        test "dynamic_tools/1 returns normalizable dynamic tool specs" do
          tools = @adapter.dynamic_tools(@config)

          assert is_list(tools)
          assert Enum.all?(tools, &is_map/1)
          assert Enum.all?(tools, &match?({:ok, _tool_spec}, Spec.normalize(&1)))
        end
      end

      if unquote(execute_dynamic_tool?) do
        test "execute_dynamic_tool/4 returns a tagged tool result" do
          assert adapter_contract_tool_result?(@adapter.execute_dynamic_tool(@config, "__contract_unsupported__", %{}, []))
        end
      end

      if unquote(project_ref?) do
        test "project_ref/1 returns a project ref or nil" do
          result = @adapter.project_ref(@config)

          assert is_nil(result) or is_struct(result, ProjectRef)

          if is_struct(result, ProjectRef) do
            assert result.kind == @adapter.kind()
          end
        end
      end

      if unquote(fetch_candidate_issues?) do
        test "fetch_candidate_issues/2 returns {:ok, list} or {:error, _}" do
          assert adapter_contract_list_result?(@adapter.fetch_candidate_issues(@config, []))
        end
      end

      if unquote(fetch_issues_by_states?) do
        test "fetch_issues_by_states/3 returns {:ok, list} or {:error, _}" do
          assert adapter_contract_list_result?(@adapter.fetch_issues_by_states(@config, ["todo"], []))
        end
      end

      if unquote(fetch_issue_states_by_ids?) do
        test "fetch_issue_states_by_ids/3 returns {:ok, list} or {:error, _}" do
          assert adapter_contract_list_result?(@adapter.fetch_issue_states_by_ids(@config, ["issue-1"], []))
        end
      end

      if unquote(create_comment?) do
        test "create_comment/4 returns :ok or {:error, _}" do
          assert adapter_contract_write_result?(@adapter.create_comment(@config, "issue-1", "contract comment", []))
        end
      end

      if unquote(update_issue_state?) do
        test "update_issue_state/4 returns :ok or {:error, _}" do
          assert adapter_contract_write_result?(@adapter.update_issue_state(@config, "issue-1", "done", []))
        end
      end

      if unquote(prepare_workspace?) do
        test "prepare_workspace/3 returns :ok or {:error, _}" do
          workspace =
            Path.join(
              System.tmp_dir!(),
              "tracker-adapter-contract-#{System.unique_integer([:positive])}"
            )

          File.mkdir_p!(workspace)
          on_exit(fn -> File.rm_rf(workspace) end)

          assert adapter_contract_write_result?(@adapter.prepare_workspace(@config, workspace, []))
        end
      end

      if unquote(healthcheck?) do
        test "healthcheck/2 returns :ok or {:error, _}" do
          assert adapter_contract_write_result?(@adapter.healthcheck(@config, []))
        end
      end

      defp adapter_contract_list_result?(result) do
        match?({:ok, values} when is_list(values), result) or match?({:error, _reason}, result)
      end

      defp adapter_contract_write_result?(result) do
        result == :ok or match?({:error, _reason}, result)
      end

      defp adapter_contract_tool_result?(result) do
        match?({:success, _payload}, result) or
          match?({:failure, _payload}, result) or
          match?({:error, _reason}, result)
      end
    end
  end
end
