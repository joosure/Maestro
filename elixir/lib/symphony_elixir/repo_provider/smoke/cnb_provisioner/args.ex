defmodule SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.Args do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CommandNames
  alias SymphonyElixir.RepoProvider.Smoke.ProbeRunner

  @pr_create_command CommandNames.pr_create()

  @spec provider_argv(nil | String.t(), [String.t()]) :: [String.t()]
  def provider_argv(nil, argv), do: argv
  def provider_argv(provider_override, argv), do: ["--provider", provider_override | argv]

  @spec destructive_create_argv(String.t(), String.t(), String.t() | nil, String.t() | nil) :: [String.t()]
  def destructive_create_argv(title, body, base, head) do
    [@pr_create_command, "--title", title, "--body", body]
    |> maybe_append_option("--base", base)
    |> maybe_append_option("--head", head)
  end

  @spec destructive_edited_body(String.t()) :: String.t()
  def destructive_edited_body(create_body) do
    create_body <> "\n\nEdited by Symphony repo-provider destructive smoke."
  end

  @spec created_pull(map()) :: {:ok, String.t(), String.t()} | {:error, String.t()}
  def created_pull(%{ok: false}), do: {:error, "Unable to resolve a created PR because pr-create failed"}

  def created_pull(%{stdout: stdout}) do
    case stdout |> String.split("\n", trim: true) |> List.first() |> ProbeRunner.blank_to_nil() do
      nil ->
        {:error, "Unable to determine created PR URL from pr-create output"}

      url ->
        case Regex.run(~r{/(?:pull|pulls)/(\d+)$}, url, capture: :all_but_first) do
          [number] -> {:ok, url, number}
          _other -> {:error, "Unable to determine created PR number from pr-create output: #{url}"}
        end
    end
  end

  defp maybe_append_option(argv, _flag, nil), do: argv
  defp maybe_append_option(argv, _flag, ""), do: argv
  defp maybe_append_option(argv, flag, value), do: argv ++ [flag, value]
end
