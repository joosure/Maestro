defmodule SymphonyElixir.Workflow.Template.Assets do
  @moduledoc """
  Path resolver for workflow template assets stored under OTP application `priv/`.

  This module owns only asset-root path mechanics. Template registries and
  workflow extensions own template metadata; plugin manifests or extension
  contributions own concrete template entries.
  """

  alias SymphonyElixir.Workflow.Template.PathRules

  @default_otp_app :symphony_elixir

  @spec app_priv_root!(Path.t(), keyword()) :: Path.t()
  def app_priv_root!(relative_dir, opts \\ []) when is_binary(relative_dir) and is_list(opts) do
    otp_app = Keyword.get(opts, :otp_app, @default_otp_app)

    otp_app
    |> priv_dir!()
    |> Path.join(validate_relative_dir!(relative_dir))
    |> Path.expand()
  end

  defp priv_dir!(otp_app) when is_atom(otp_app) and not is_nil(otp_app) do
    case :code.priv_dir(otp_app) do
      path when is_list(path) ->
        to_string(path)

      {:error, reason} ->
        raise ArgumentError,
              "could not resolve priv directory for otp_app #{inspect(otp_app)}: #{inspect(reason)}"
    end
  end

  defp priv_dir!(otp_app) do
    raise ArgumentError, "template asset otp_app must be an atom, got #{inspect(otp_app)}"
  end

  defp validate_relative_dir!(relative_dir) do
    relative_dir = String.trim(relative_dir)
    segments = Path.split(relative_dir)

    cond do
      relative_dir == "" ->
        raise ArgumentError, "template asset root must be non-empty"

      Path.type(relative_dir) == :absolute ->
        raise ArgumentError, "template asset root must be relative"

      PathRules.contains_forbidden_relative_segment?(segments) ->
        raise ArgumentError, "template asset root must stay under the application priv directory"

      true ->
        Path.join(segments)
    end
  end
end
