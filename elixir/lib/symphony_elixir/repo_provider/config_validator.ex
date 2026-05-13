defmodule SymphonyElixir.RepoProvider.ConfigValidator do
  @moduledoc """
  Shared validator for normalized repo-provider configuration.

  This module owns validation for canonical, cross-adapter repo-provider
  options. Adapters remain free to implement deeper provider-specific
  checks, but shared option support should be declared through
  `supported_config_options/0` and validated here.

  Keeping these rules outside adapter implementations makes it easier to:

    * add new shared options without duplicating logic
    * inspect which adapters support which options
    * keep adapter modules focused on provider behavior
  """

  alias SymphonyElixir.RepoProvider.ChangeProposalBody
  alias SymphonyElixir.RepoProvider.Config, as: RepoConfig
  alias SymphonyElixir.RepoProvider.Error

  @type option_key :: :required_pr_label | :change_proposal_body_generator

  @option_specs %{
    required_pr_label: %{
      canonical_path: "repo.provider.options.required_pr_label"
    },
    change_proposal_body_generator: %{
      canonical_path: "repo.provider.options.change_proposal_body_generator"
    }
  }

  @spec validate(RepoConfig.t() | map(), module()) :: :ok | {:error, Error.t()}
  def validate(repo, adapter_module) when is_atom(adapter_module) do
    config = RepoConfig.new(repo)
    kind = repo_provider_kind(config, adapter_module)

    with :ok <- validate_supported_options(config, adapter_module, kind),
         :ok <- validate_option_values(config, kind) do
      :ok
    end
  end

  @spec known_options() :: [option_key()]
  def known_options, do: Map.keys(@option_specs)

  @spec supported_config_options(module()) :: [option_key()]
  def supported_config_options(adapter_module) when is_atom(adapter_module) do
    Code.ensure_loaded(adapter_module)

    if function_exported?(adapter_module, :supported_config_options, 0) do
      adapter_module.supported_config_options()
      |> Enum.filter(&Map.has_key?(@option_specs, &1))
    else
      []
    end
  end

  @spec canonical_path(option_key()) :: String.t() | nil
  def canonical_path(option) when is_atom(option) do
    @option_specs
    |> Map.get(option, %{})
    |> Map.get(:canonical_path)
  end

  defp validate_supported_options(config, adapter_module, kind) do
    config
    |> present_options()
    |> Enum.find_value(:ok, fn {option, _value} ->
      if supports_option?(adapter_module, option) do
        nil
      else
        {:error, Error.unsupported_option(kind, option)}
      end
    end)
  end

  defp validate_option_values(config, kind) do
    case ChangeProposalBody.validate_generator(RepoConfig.change_proposal_body_generator(config)) do
      :ok -> :ok
      {:error, {:invalid_arguments, message}} -> {:error, Error.invalid_option(kind, :change_proposal_body_generator, message)}
    end
  end

  defp present_options(config) do
    known_options()
    |> Enum.reduce([], fn option, acc ->
      case option_value(config, option) do
        value when is_binary(value) ->
          if String.trim(value) != "" do
            [{option, value} | acc]
          else
            acc
          end

        value when is_map(value) ->
          [{option, value} | acc]

        value when is_atom(value) and not is_nil(value) ->
          [{option, value} | acc]

        _other ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  defp option_value(repo, :required_pr_label), do: RepoConfig.required_pr_label(repo)
  defp option_value(repo, :change_proposal_body_generator), do: RepoConfig.change_proposal_body_generator(repo)

  defp supports_option?(adapter_module, option) when is_atom(adapter_module) and is_atom(option) do
    option in supported_config_options(adapter_module)
  end

  defp repo_provider_kind(config, adapter_module) do
    RepoConfig.kind(config) || adapter_kind(adapter_module)
  end

  defp adapter_kind(adapter_module) when is_atom(adapter_module) do
    Code.ensure_loaded(adapter_module)

    if function_exported?(adapter_module, :kind, 0) do
      adapter_module.kind()
    end
  end
end
