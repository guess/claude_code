defmodule ClaudeCode.History.SessionInfoTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.History.SessionInfo

  @moduletag :history

  describe "struct" do
    test "creates with all fields" do
      info = %SessionInfo{
        session_id: "550e8400-e29b-41d4-a716-446655440000",
        summary: "Test conversation",
        last_modified: 1_700_000_000_000,
        file_size: 1024,
        custom_title: "My Title",
        first_prompt: "Hello world",
        git_branch: "main",
        cwd: "/test/project"
      }

      assert info.session_id == "550e8400-e29b-41d4-a716-446655440000"
      assert info.summary == "Test conversation"
      assert info.last_modified == 1_700_000_000_000
      assert info.file_size == 1024
      assert info.custom_title == "My Title"
      assert info.first_prompt == "Hello world"
      assert info.git_branch == "main"
      assert info.cwd == "/test/project"
    end

    test "defaults to nil for optional fields" do
      info = %SessionInfo{
        session_id: "test",
        summary: "Test",
        last_modified: 0,
        file_size: 0
      }

      assert is_nil(info.custom_title)
      assert is_nil(info.first_prompt)
      assert is_nil(info.git_branch)
      assert is_nil(info.cwd)
    end
  end

  describe "JSON encoding" do
    test "encodes to JSON with nil values stripped" do
      info = %SessionInfo{
        session_id: "test-id",
        summary: "Test",
        last_modified: 1000,
        file_size: 512,
        custom_title: nil,
        first_prompt: "Hello"
      }

      {:ok, json} = Jason.encode(info)
      decoded = Jason.decode!(json)

      assert decoded["session_id"] == "test-id"
      assert decoded["summary"] == "Test"
      assert decoded["first_prompt"] == "Hello"
      refute Map.has_key?(decoded, "custom_title")
      refute Map.has_key?(decoded, "git_branch")
      refute Map.has_key?(decoded, "cwd")
    end
  end
end
