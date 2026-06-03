defmodule SymphonyElixir.CLIEntrypointTest do
  use ExUnit.Case, async: true

  test "mix build writes the generated escript beside the stable launcher" do
    escript = Keyword.fetch!(Mix.Project.config(), :escript)

    assert Keyword.fetch!(escript, :path) == "bin/symphony.escript"
    assert Keyword.fetch!(escript, :emu_args) == "+B i"
  end

  test "bin/symphony remains the source-controlled launcher wrapper" do
    launcher = Path.expand("bin/symphony")
    contents = File.read!(launcher)

    assert File.regular?(launcher)
    assert String.starts_with?(contents, "#!/usr/bin/env bash\n")
    assert contents =~ ~s(payload="${script_dir}/symphony.escript")
    refute contents =~ "%%! -escript"
  end
end
