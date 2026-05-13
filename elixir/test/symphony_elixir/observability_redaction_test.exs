defmodule SymphonyElixir.Observability.RedactionTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Observability.Redaction

  setup do
    Redaction.configure_from_observability(%{})

    on_exit(fn ->
      Redaction.configure_from_observability(%{})
    end)

    :ok
  end

  test "redact masks sensitive map keys recursively" do
    redacted =
      Redaction.redact(%{
        api_key: "linear-token",
        api_token: "provider-token",
        nested: %{
          "authorization" => "Bearer abc123",
          "safe" => "value"
        }
      })

    assert redacted["api_key"] == "[REDACTED]"
    assert redacted["api_token"] == "[REDACTED]"
    assert redacted["nested"]["authorization"] == "[REDACTED]"
    assert redacted["nested"]["safe"] == "value"
  end

  test "redact preserves non-secret token metrics" do
    redacted =
      Redaction.redact(%{
        total_tokens: 42,
        input_tokens: 10,
        output_tokens: 32,
        max_tokens: 100,
        token_count: 4,
        prompt_tokens: 2,
        access_token: "secret"
      })

    assert redacted["total_tokens"] == 42
    assert redacted["input_tokens"] == 10
    assert redacted["output_tokens"] == 32
    assert redacted["max_tokens"] == 100
    assert redacted["token_count"] == 4
    assert redacted["prompt_tokens"] == 2
    assert redacted["access_token"] == "[REDACTED]"
  end

  test "redact_string masks bearer tokens and plain secret assignments" do
    text =
      "Authorization: Bearer abc123 TAPD_API_PASSWORD=super-secret LINEAR_API_KEY=token-1 token=abc password=foo authorization: sk-123"

    redacted = Redaction.redact_string(text)

    assert redacted =~ "Authorization: [REDACTED]"
    assert redacted =~ "TAPD_API_PASSWORD=[REDACTED]"
    assert redacted =~ "LINEAR_API_KEY=[REDACTED]"
    assert redacted =~ "token=[REDACTED]"
    assert redacted =~ "password=[REDACTED]"
    assert redacted =~ "authorization: [REDACTED]"
    refute redacted =~ "abc123"
    refute redacted =~ "super-secret"
    refute redacted =~ "token-1"
    refute redacted =~ "sk-123"
  end

  test "redact_string masks JSON-like secret assignments" do
    text = ~s({"token":"abc123","api_key":"secret-key","safe":"value"})

    redacted = Redaction.redact_string(text)

    assert redacted =~ ~s("token":"[REDACTED]")
    assert redacted =~ ~s("api_key":"[REDACTED]")
    assert redacted =~ ~s("safe":"value")
    refute redacted =~ "abc123"
    refute redacted =~ "secret-key"
  end

  test "redact_string masks bare provider token values in command output" do
    redacted = Redaction.redact_string("provider failed with token sk-secret and ghp_abc123")

    assert redacted =~ "[REDACTED]"
    refute redacted =~ "sk-secret"
    refute redacted =~ "ghp_abc123"
  end

  test "redact_string masks OpenCode env-token credentials" do
    text = "OPENROUTER_API_KEY=sk-or-v1-secret provider returned sk-or-v1-other-secret"
    redacted = Redaction.redact_string(text)

    assert redacted =~ "OPENROUTER_API_KEY=[REDACTED]"
    refute redacted =~ "sk-or-v1-secret"
    refute redacted =~ "sk-or-v1-other-secret"
  end

  test "summarize truncates long payloads after redaction" do
    summary = Redaction.summarize(%{"message" => String.duplicate("x", 600)}, 80)

    assert summary =~ "xxxxxxxx"
    assert summary =~ "<truncated>"
  end

  test "summarize uses configured summary_max_bytes by default" do
    Redaction.configure_from_observability(%{summary_max_bytes: 40})
    summary = Redaction.summarize(%{"message" => String.duplicate("x", 200)})

    assert byte_size(summary) <= 54
    assert summary =~ "<truncated>"
  end

  test "summarize keeps truncated unicode valid" do
    summary = Redaction.summarize(String.duplicate("汉", 10), 5)

    assert String.valid?(summary)
    assert summary =~ "<truncated>"
  end
end
