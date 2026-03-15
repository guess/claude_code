defmodule ClaudeCode.History.WorktreeTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.History.Worktree

  @moduletag :history

  describe "list_paths/1" do
    test "returns paths for a git repository" do
      # Use the current repo as a test subject
      {:ok, paths} = Worktree.list_paths(File.cwd!())
      assert is_list(paths)
      # At minimum, the main worktree should be returned
      assert length(paths) >= 1
    end

    test "returns empty list for non-git directory" do
      {:ok, paths} = Worktree.list_paths(System.tmp_dir!())
      assert paths == []
    end

    test "returns empty list for non-existent directory" do
      {:ok, paths} = Worktree.list_paths("/nonexistent/path/that/does/not/exist")
      assert paths == []
    end
  end
end
