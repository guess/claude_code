defmodule ClaudeCode.Content.ContainerUploadBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.ContainerUploadBlock

  describe "new/1" do
    test "parses valid container_upload block" do
      data = %{"type" => "container_upload", "file_id" => "file_abc123"}

      assert {:ok, block} = ContainerUploadBlock.new(data)
      assert block.type == :container_upload
      assert block.file_id == "file_abc123"
    end

    test "returns error when file_id is missing" do
      assert {:error, {:missing_fields, [:file_id]}} =
               ContainerUploadBlock.new(%{"type" => "container_upload"})
    end

    test "returns error for wrong type" do
      assert {:error, :invalid_content_type} =
               ContainerUploadBlock.new(%{"type" => "text", "file_id" => "f"})
    end

    test "returns error for non-map input" do
      assert {:error, :invalid_content_type} = ContainerUploadBlock.new("not a map")
    end
  end

  describe "JSON encoding" do
    test "encodes to JSON via Jason" do
      block = %ContainerUploadBlock{type: :container_upload, file_id: "file_123"}

      assert {:ok, json} = Jason.encode(block)
      decoded = Jason.decode!(json)
      assert decoded["type"] == "container_upload"
      assert decoded["file_id"] == "file_123"
    end

    test "encodes to JSON via JSON" do
      block = %ContainerUploadBlock{type: :container_upload, file_id: "file_123"}

      json = JSON.encode!(block)
      decoded = Jason.decode!(json)
      assert decoded["type"] == "container_upload"
    end
  end
end
