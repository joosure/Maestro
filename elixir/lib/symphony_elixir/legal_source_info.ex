defmodule SymphonyElixir.LegalSourceInfo do
  @moduledoc """
  Source availability metadata for AGPL network interaction notices.
  """

  alias SymphonyElixir.LegalSourceInfo.RuntimeEnv

  @spec payload(keyword()) :: map()
  def payload(opts \\ []) when is_list(opts) do
    %{
      "license" => "AGPL-3.0-only",
      "source_url" => source_url(),
      "source_revision" => source_revision(),
      "notice_path" => Keyword.get(opts, :notice_path),
      "inherited_license_file" => "LICENSES/Apache-2.0.txt",
      "modification_notice_file" => "MODIFICATIONS.md",
      "source_guidance_file" => "SOURCE.md",
      "third_party_license_file" => "THIRD_PARTY_LICENSES.md"
    }
  end

  @spec source_url() :: String.t()
  def source_url, do: RuntimeEnv.source_url()

  @spec source_revision() :: String.t() | nil
  def source_revision, do: RuntimeEnv.source_revision()
end
