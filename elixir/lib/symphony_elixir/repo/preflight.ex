defmodule SymphonyElixir.Repo.Preflight do
  @moduledoc """
  Provider-neutral repository preflight result.

  A preflight result captures the repo facts needed before workflow execution
  starts mutating a target repository.
  """

  @enforce_keys [:path, :root, :remote, :remote_url, :base_branch, :current_branch, :head_sha]
  defstruct [:path, :root, :remote, :remote_url, :base_branch, :current_branch, :head_sha]

  @type t :: %__MODULE__{
          path: Path.t(),
          root: Path.t(),
          remote: String.t(),
          remote_url: String.t(),
          base_branch: String.t(),
          current_branch: String.t(),
          head_sha: String.t()
        }
end
