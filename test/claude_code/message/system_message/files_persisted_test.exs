defmodule ClaudeCode.Message.SystemMessage.FilesPersistedTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage.FilesPersisted

  describe "new/1" do
    test "parses a valid files_persisted message with file list" do
      json = %{
        "type" => "system",
        "subtype" => "files_persisted",
        "files" => [
          %{"filename" => "example.ex", "file_id" => "file-abc123"},
          %{"filename" => "test.ex", "file_id" => "file-def456"}
        ],
        "failed" => [
          %{"filename" => "bad.ex", "error" => "Permission denied"}
        ],
        "processed_at" => "2025-01-15T10:30:00Z",
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = FilesPersisted.new(json)
      assert message.type == :system
      assert message.subtype == :files_persisted
      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
      assert message.processed_at == "2025-01-15T10:30:00Z"

      assert message.files == [
               %{filename: "example.ex", file_id: "file-abc123"},
               %{filename: "test.ex", file_id: "file-def456"}
             ]

      assert message.failed == [
               %{filename: "bad.ex", error: "Permission denied"}
             ]
    end

    test "parses files array into maps with :filename and :file_id keys" do
      json = %{
        "type" => "system",
        "subtype" => "files_persisted",
        "files" => [%{"filename" => "lib/app.ex", "file_id" => "file-1"}],
        "session_id" => "session-abc"
      }

      assert {:ok, message} = FilesPersisted.new(json)
      assert [%{filename: "lib/app.ex", file_id: "file-1"}] = message.files
    end

    test "handles empty files list" do
      json = %{
        "type" => "system",
        "subtype" => "files_persisted",
        "files" => [],
        "session_id" => "session-abc"
      }

      assert {:ok, message} = FilesPersisted.new(json)
      assert message.files == []
    end

    test "handles absent optional keys" do
      json = %{
        "type" => "system",
        "subtype" => "files_persisted",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = FilesPersisted.new(json)
      assert message.files == []
      assert message.failed == []
      assert message.processed_at == nil
    end

    test "filters out malformed file entries" do
      json = %{
        "type" => "system",
        "subtype" => "files_persisted",
        "files" => [
          %{"filename" => "good.ex", "file_id" => "file-1"},
          %{"bad_key" => "value"},
          %{"filename" => "also_good.ex", "file_id" => "file-2"}
        ],
        "session_id" => "session-abc"
      }

      assert {:ok, message} = FilesPersisted.new(json)

      assert message.files == [
               %{filename: "good.ex", file_id: "file-1"},
               %{filename: "also_good.ex", file_id: "file-2"}
             ]
    end

    test "returns error for missing session_id" do
      json = %{"type" => "system", "subtype" => "files_persisted"}
      assert {:error, :missing_required_fields} = FilesPersisted.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = FilesPersisted.new(json)
    end

    test "filters out malformed failed entries" do
      json = %{
        "type" => "system",
        "subtype" => "files_persisted",
        "files" => [],
        "failed" => [
          %{"filename" => "bad.ex", "error" => "Permission denied"},
          %{"bad_key" => "value"}
        ],
        "session_id" => "session-abc"
      }

      assert {:ok, message} = FilesPersisted.new(json)
      assert message.failed == [%{filename: "bad.ex", error: "Permission denied"}]
    end
  end

  describe "files_persisted?/1" do
    test "returns true for a FilesPersisted struct" do
      message = %FilesPersisted{
        type: :system,
        subtype: :files_persisted,
        session_id: "session-1"
      }

      assert FilesPersisted.files_persisted?(message) == true
    end

    test "returns false for other values" do
      assert FilesPersisted.files_persisted?(%{}) == false
      assert FilesPersisted.files_persisted?(nil) == false
      assert FilesPersisted.files_persisted?("string") == false
    end
  end
end
