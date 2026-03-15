defmodule ClaudeCode.History.Worktree do
  @moduledoc """
  Git worktree discovery for session history scanning.

  Discovers all git worktree paths for a directory, enabling session listing
  that spans worktree boundaries.
  """

  @doc """
  Lists git worktree paths for the repository containing `directory`.

  Returns `{:ok, [path]}` with absolute paths, or `{:ok, []}` if git
  is unavailable or the directory is not in a git repository.
  """
  @spec list_paths(Path.t()) :: {:ok, [Path.t()]}
  def list_paths(directory) do
    case System.cmd("git", ["worktree", "list", "--porcelain"], cd: directory, stderr_to_stdout: true) do
      {output, 0} ->
        paths =
          output
          |> String.split("\n")
          |> Enum.flat_map(fn
            "worktree " <> path -> [String.trim(path)]
            _ -> []
          end)

        {:ok, paths}

      _ ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end
end
