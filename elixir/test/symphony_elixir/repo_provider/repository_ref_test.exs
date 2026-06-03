defmodule SymphonyElixir.RepoProvider.RepositoryRefTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.RepoProvider.RepositoryRef

  test "infers repository path from HTTPS clone URLs" do
    assert RepositoryRef.infer_from_remote_url("https://github.com/acme/widgets.git") ==
             "acme/widgets"

    assert RepositoryRef.infer_from_remote_url("https://cnb.cool/acme/widgets.git") ==
             "acme/widgets"

    assert RepositoryRef.infer_from_remote_url("https://cnb.cool/org/group/widgets.git") ==
             "org/group/widgets"

    assert RepositoryRef.infer_from_remote_url("https://github.com/acme/widgets") ==
             "acme/widgets"
  end

  test "infers repository path from SSH scp-like clone URLs" do
    assert RepositoryRef.infer_from_remote_url("git@github.com:acme/widgets.git") ==
             "acme/widgets"

    assert RepositoryRef.infer_from_remote_url("git@cnb.cool:org/group/widgets.git") ==
             "org/group/widgets"
  end

  test "does not infer ambiguous or local paths" do
    assert RepositoryRef.infer_from_remote_url(nil) == nil
    assert RepositoryRef.infer_from_remote_url("") == nil
    assert RepositoryRef.infer_from_remote_url("https://github.com/acme") == nil
    assert RepositoryRef.infer_from_remote_url("/tmp/acme/widgets") == nil
    assert RepositoryRef.infer_from_remote_url("not-a-url") == nil
  end
end
