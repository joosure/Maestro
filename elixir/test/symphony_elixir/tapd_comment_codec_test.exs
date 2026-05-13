defmodule SymphonyElixir.TapdCommentCodecTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Tracker.Tapd.CommentCodec

  test "encodes markdown workpad structure to html" do
    markdown = """
    ### Plan
    - [x] Update STATUS.txt
    - pr_url: https://github.com/org/repo/pull/123
    """

    html = CommentCodec.encode_description(markdown)

    assert html =~ "<h3>Plan</h3>"
    assert html =~ "<li>[x] Update STATUS.txt</li>"
    assert html =~ "<a href=\"https://github.com/org/repo/pull/123\""
  end

  test "decodes rendered workpad html back to markdown" do
    markdown = """
    ### Plan
    - [x] Update STATUS.txt
    - pr_url: https://github.com/org/repo/pull/123

    ### Validation
    - [x] `git diff --check`
    """

    assert String.trim_trailing(CommentCodec.decode_description(CommentCodec.encode_description(markdown))) ==
             String.trim_trailing(markdown)
  end
end
