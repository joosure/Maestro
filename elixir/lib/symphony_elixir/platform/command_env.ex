defmodule SymphonyElixir.Platform.CommandEnv do
  @moduledoc false

  @sensitive_env_name ~r/(TOKEN|SECRET|PASSWORD|API_KEY|API_SECRET|AUTHORIZATION|CREDENTIAL|PRIVATE_KEY)/i

  @allowed_sensitive_env_by_command %{
    "gh" => ~w[GH_TOKEN GITHUB_TOKEN GITHUB_ENTERPRISE_TOKEN],
    "cnb" => ~w[CNB_TOKEN]
  }

  @type env :: %{optional(String.t()) => String.t() | nil} | [{String.t(), String.t() | nil}]

  @spec scrubbed(keyword()) :: [{String.t(), nil}]
  def scrubbed(opts \\ []) when is_list(opts) do
    allowed =
      opts
      |> Keyword.get(:allow, [])
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    System.get_env()
    |> Map.keys()
    |> Enum.filter(&sensitive_env_name?/1)
    |> Enum.reject(&MapSet.member?(allowed, &1))
    |> Enum.sort()
    |> Enum.map(&{&1, nil})
  end

  @spec merge(env() | nil, keyword()) :: [{String.t(), String.t() | nil}]
  def merge(env, opts \\ []) do
    opts
    |> scrubbed()
    |> Map.new()
    |> Map.merge(normalize_env(env))
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  @spec system_cmd(String.t(), [String.t()], keyword()) :: {String.t(), non_neg_integer()}
  def system_cmd(command, args, opts \\ []) when is_binary(command) and is_list(args) and is_list(opts) do
    {allowed_sensitive_env, opts} = Keyword.pop(opts, :allow_sensitive_env, [])

    allowed_sensitive_env =
      command
      |> command_allowed_sensitive_env()
      |> Kernel.++(Enum.map(allowed_sensitive_env, &to_string/1))

    env =
      opts
      |> Keyword.get(:env)
      |> merge(allow: allowed_sensitive_env)

    System.cmd(command, args, Keyword.put(opts, :env, env))
  end

  defp normalize_env(nil), do: %{}
  defp normalize_env(env) when is_map(env), do: Map.new(env, &normalize_env_entry/1)
  defp normalize_env(env) when is_list(env), do: env |> Map.new() |> normalize_env()

  defp normalize_env_entry({key, nil}), do: {to_string(key), nil}
  defp normalize_env_entry({key, value}), do: {to_string(key), to_string(value)}

  defp sensitive_env_name?(name) when is_binary(name), do: String.match?(name, @sensitive_env_name)

  defp command_allowed_sensitive_env(command) when is_binary(command) do
    command
    |> Path.basename()
    |> then(&Map.get(@allowed_sensitive_env_by_command, &1, []))
  end
end
