defmodule ClaudeCode.RewindFilesResultTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.RewindFilesResult

  describe "new/1" do
    test "parses successful rewind result" do
      data = %{
        "canRewind" => true,
        "filesChanged" => ["lib/app.ex", "test/app_test.exs"],
        "insertions" => 10,
        "deletions" => 3
      }

      result = RewindFilesResult.new(data)

      assert result.can_rewind == true
      assert result.error == nil
      assert result.files_changed == ["lib/app.ex", "test/app_test.exs"]
      assert result.insertions == 10
      assert result.deletions == 3
    end

    test "parses failed rewind result" do
      data = %{
        "canRewind" => false,
        "error" => "No checkpoints available"
      }

      result = RewindFilesResult.new(data)

      assert result.can_rewind == false
      assert result.error == "No checkpoints available"
      assert result.files_changed == nil
    end
  end

  describe "Jason.Encoder" do
    test "encodes to JSON" do
      result = %RewindFilesResult{can_rewind: true, files_changed: ["a.ex"], insertions: 5, deletions: 2}
      json = Jason.encode!(result)
      decoded = Jason.decode!(json)

      assert decoded["can_rewind"] == true
      assert decoded["files_changed"] == ["a.ex"]
    end
  end
end
