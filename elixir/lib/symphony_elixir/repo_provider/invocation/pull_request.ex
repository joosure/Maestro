defmodule SymphonyElixir.RepoProvider.Invocation.PullRequest do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Invocation
  alias SymphonyElixir.RepoProvider.Invocation.Options

  @spec parse_view([String.t()], Invocation.t()) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse_view([], invocation), do: {:ok, invocation}

  def parse_view(["--json", fields | rest], invocation) do
    parse_view(rest, %{invocation | json_fields: Options.fields(fields)})
  end

  def parse_view(["--json"], _invocation) do
    {:error, Error.invalid_invocation("Option --json requires a value")}
  end

  def parse_view([flag, expr | rest], invocation) when flag in ["-q", "--jq"] do
    parse_view(rest, %{invocation | jq: expr})
  end

  def parse_view([flag], _invocation) when flag in ["-q", "--jq"] do
    {:error, Error.invalid_invocation("Option #{flag} requires a value")}
  end

  def parse_view([number | rest], %Invocation{number: nil} = invocation)
      when is_binary(number) do
    if String.starts_with?(number, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-view option: #{number}")}
    else
      parse_view(rest, %{invocation | number: number})
    end
  end

  def parse_view([arg | _rest], _invocation) do
    {:error, Error.invalid_invocation("Unsupported pr-view option: #{arg}")}
  end

  @spec parse_mutation([String.t()], Invocation.t()) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse_mutation([], invocation), do: {:ok, invocation}

  def parse_mutation([flag, value | rest], invocation)
      when flag in ["--title", "--body", "--base", "--head"] do
    invocation =
      case flag do
        "--title" -> %{invocation | title: value}
        "--body" -> %{invocation | body: value}
        "--base" -> %{invocation | base: value}
        "--head" -> %{invocation | head: value}
      end

    parse_mutation(rest, invocation)
  end

  def parse_mutation([flag], _invocation)
      when flag in ["--title", "--body", "--base", "--head"] do
    {:error, Error.invalid_invocation("Option #{flag} requires a value")}
  end

  def parse_mutation(["--body-file", path | rest], invocation) do
    with {:ok, body} <- Options.body_file(path) do
      parse_mutation(rest, %{invocation | body: body})
    end
  end

  def parse_mutation(["--body-file"], _invocation) do
    {:error, Error.invalid_invocation("Option --body-file requires a value")}
  end

  def parse_mutation([number | rest], %Invocation{number: nil} = invocation)
      when is_binary(number) do
    if String.starts_with?(number, "-") do
      {:error, Error.invalid_invocation("Unsupported PR mutation option: #{number}")}
    else
      parse_mutation(rest, %{invocation | number: number})
    end
  end

  def parse_mutation([arg | _rest], _invocation) when is_binary(arg) do
    if String.starts_with?(arg, "-") do
      {:error, Error.invalid_invocation("Unsupported PR mutation option: #{arg}")}
    else
      {:error, Error.invalid_invocation("Unexpected PR mutation argument: #{arg}")}
    end
  end

  @spec parse_close([String.t()], Invocation.t()) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse_close([], invocation), do: {:ok, invocation}

  def parse_close(["--comment", comment | rest], invocation) do
    parse_close(rest, %{invocation | comment: comment})
  end

  def parse_close(["--comment"], _invocation) do
    {:error, Error.invalid_invocation("Option --comment requires a value")}
  end

  def parse_close([number | rest], %Invocation{number: nil} = invocation)
      when is_binary(number) do
    if String.starts_with?(number, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-close option: #{number}")}
    else
      parse_close(rest, %{invocation | number: number})
    end
  end

  def parse_close([arg | _rest], _invocation) when is_binary(arg) do
    if String.starts_with?(arg, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-close option: #{arg}")}
    else
      {:error, Error.invalid_invocation("Unexpected pr-close argument: #{arg}")}
    end
  end

  @spec parse_add_label([String.t()], Invocation.t()) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse_add_label([], %Invocation{label: nil}) do
    {:error, Error.invalid_invocation("pr-add-label requires a label")}
  end

  def parse_add_label([], invocation), do: {:ok, invocation}

  def parse_add_label(["--label", label | rest], invocation) do
    parse_add_label(rest, %{invocation | label: label})
  end

  def parse_add_label(["--label"], _invocation) do
    {:error, Error.invalid_invocation("Option --label requires a value")}
  end

  def parse_add_label([label | rest], %Invocation{label: nil} = invocation)
      when is_binary(label) do
    if String.starts_with?(label, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-add-label option: #{label}")}
    else
      parse_add_label(rest, %{invocation | label: label})
    end
  end

  def parse_add_label([number | rest], %Invocation{number: nil} = invocation)
      when is_binary(number) do
    if String.starts_with?(number, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-add-label option: #{number}")}
    else
      parse_add_label(rest, %{invocation | number: number})
    end
  end

  def parse_add_label([arg | _rest], _invocation) when is_binary(arg) do
    if String.starts_with?(arg, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-add-label option: #{arg}")}
    else
      {:error, Error.invalid_invocation("Unexpected pr-add-label argument: #{arg}")}
    end
  end

  @spec parse_merge([String.t()], Invocation.t()) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse_merge([], invocation), do: {:ok, invocation}

  def parse_merge(["--squash" | rest], invocation) do
    parse_merge(rest, %{invocation | merge_style: "squash"})
  end

  def parse_merge(["--rebase" | rest], invocation) do
    parse_merge(rest, %{invocation | merge_style: "rebase"})
  end

  def parse_merge(["--merge" | rest], invocation) do
    parse_merge(rest, %{invocation | merge_style: "merge"})
  end

  def parse_merge(["--subject", subject | rest], invocation) do
    parse_merge(rest, %{invocation | subject: subject})
  end

  def parse_merge(["--subject"], _invocation) do
    {:error, Error.invalid_invocation("Option --subject requires a value")}
  end

  def parse_merge(["--body", body | rest], invocation) do
    parse_merge(rest, %{invocation | body: body})
  end

  def parse_merge(["--body"], _invocation) do
    {:error, Error.invalid_invocation("Option --body requires a value")}
  end

  def parse_merge([number | rest], %Invocation{number: nil} = invocation)
      when is_binary(number) do
    if String.starts_with?(number, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-merge option: #{number}")}
    else
      parse_merge(rest, %{invocation | number: number})
    end
  end

  def parse_merge([arg | _rest], _invocation) when is_binary(arg) do
    if String.starts_with?(arg, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-merge option: #{arg}")}
    else
      {:error, Error.invalid_invocation("Unexpected pr-merge argument: #{arg}")}
    end
  end

  @spec parse_checks([String.t()], Invocation.t()) :: {:ok, Invocation.t()} | {:error, Error.t()}
  def parse_checks([], invocation), do: {:ok, invocation}

  def parse_checks(["--watch" | rest], invocation) do
    parse_checks(rest, %{invocation | watch?: true})
  end

  def parse_checks(["--json" | rest], invocation) do
    parse_checks(rest, %{invocation | json?: true})
  end

  def parse_checks([flag, expr | rest], invocation) when flag in ["-q", "--jq"] do
    parse_checks(rest, %{invocation | jq: expr})
  end

  def parse_checks([flag], _invocation) when flag in ["-q", "--jq"] do
    {:error, Error.invalid_invocation("Option #{flag} requires a value")}
  end

  def parse_checks([number | rest], %Invocation{number: nil} = invocation)
      when is_binary(number) do
    if String.starts_with?(number, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-checks option: #{number}")}
    else
      parse_checks(rest, %{invocation | number: number})
    end
  end

  def parse_checks([arg | _rest], _invocation) when is_binary(arg) do
    if String.starts_with?(arg, "-") do
      {:error, Error.invalid_invocation("Unsupported pr-checks option: #{arg}")}
    else
      {:error, Error.invalid_invocation("Unexpected pr-checks argument: #{arg}")}
    end
  end

  def parse_checks([arg | _rest], _invocation) do
    {:error, Error.invalid_invocation("Unsupported pr-checks option: #{arg}")}
  end
end
