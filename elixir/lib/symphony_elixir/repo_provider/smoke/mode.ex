defmodule SymphonyElixir.RepoProvider.Smoke.Mode do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Smoke.CNBProvisioner
  alias SymphonyElixir.RepoProvider.Smoke.ReadOnly

  @spec smoke_mode(keyword()) :: String.t()
  def smoke_mode(opts) do
    cond do
      auto_provision_cnb_pipeline?(opts) -> "destructive_auto_provision_cnb_pipeline"
      Keyword.get(opts, :destructive) -> "destructive"
      true -> "read_only"
    end
  end

  @spec planned_probe_count(keyword(), nil | String.t(), map()) :: non_neg_integer()
  def planned_probe_count(opts, provider_override, repo_config) do
    case smoke_mode(opts) do
      "destructive" -> 8
      "destructive_auto_provision_cnb_pipeline" -> 14 + if(CNBProvisioner.needs_base_resolution?(opts, repo_config), do: 1, else: 0)
      _other -> opts |> ReadOnly.build_probes(provider_override) |> length()
    end
  end

  defp auto_provision_cnb_pipeline?(opts), do: Keyword.get(opts, :auto_provision_cnb_pipeline, false)
end
