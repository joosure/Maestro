defmodule SymphonyElixir.Repo.Branch do
  @moduledoc """
  Provider-neutral branch-name helpers for repo-core workflows.
  """

  alias SymphonyElixir.Repo.Error

  @default_work_prefix "symphony"
  @max_component_length 96

  @type result(t) :: {:ok, t} | {:error, Error.t()}

  @spec working_branch(String.t(), keyword()) :: result(String.t())
  def working_branch(identifier, opts \\ [])

  def working_branch(identifier, opts) when is_binary(identifier) and is_list(opts) do
    with {:ok, identifier_component} <- identifier_component(identifier) do
      prefix = work_prefix(opts)

      branch =
        [prefix, identifier_component]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("/")

      {:ok, branch}
    end
  end

  def working_branch(_identifier, _opts) do
    {:error, Error.invalid_invocation(:working_branch, "working branch identifier is required")}
  end

  @spec work_prefix(keyword()) :: String.t()
  def work_prefix(opts \\ []) when is_list(opts) do
    opts
    |> Keyword.get(:work_prefix)
    |> present_string()
    |> case do
      nil -> System.get_env("SYMPHONY_REPO_BRANCH_WORK_PREFIX")
      value -> value
    end
    |> present_string()
    |> case do
      nil -> @default_work_prefix
      value -> value
    end
    |> normalize_prefix()
    |> case do
      nil -> @default_work_prefix
      value -> value
    end
  end

  defp identifier_component(identifier) do
    case normalize_component(identifier) do
      nil ->
        {:error, Error.invalid_invocation(:working_branch, "working branch identifier is required")}

      component ->
        {:ok, component}
    end
  end

  defp normalize_prefix(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace_prefix("refs/heads/", "")
    |> String.split("/", trim: true)
    |> Enum.map(&normalize_component/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      components -> Enum.join(components, "/")
    end
  end

  defp normalize_component(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")

    case normalized do
      "" -> nil
      component -> truncate_component(component)
    end
  end

  defp truncate_component(component) when byte_size(component) <= @max_component_length, do: component

  defp truncate_component(component) do
    hash =
      :sha256
      |> :crypto.hash(component)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 8)

    available = @max_component_length - byte_size(hash) - 1

    component
    |> binary_part(0, available)
    |> String.trim_trailing("-")
    |> Kernel.<>("-#{hash}")
  end

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_string(_value), do: nil
end
