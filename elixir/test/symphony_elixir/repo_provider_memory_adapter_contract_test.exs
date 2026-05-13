defmodule SymphonyElixir.RepoProviderMemoryAdapterContractTest do
  use ExUnit.Case, async: false

  use SymphonyElixir.RepoProviderAdapterContract,
    adapter: SymphonyElixir.RepoProvider.Memory,
    config: %{
      provider: %{
        kind: "memory",
        options: %{required_pr_label: "release-ready"}
      }
    }
end
