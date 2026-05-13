defmodule SymphonyWorkerDaemon.Session.Server.ProviderEnvironment do
  @moduledoc false

  @spec env(map(), map() | nil) :: map()
  def env(request, nil) when is_map(request), do: env_request(request)
  def env(request, %{env: bridge_env}) when is_map(request) and is_map(bridge_env), do: Map.merge(env_request(request), bridge_env)

  defp env_request(%{"env" => env}) when is_map(env), do: env
  defp env_request(_request), do: %{}
end
